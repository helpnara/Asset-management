import LocalAuthentication
import Observation
import SwiftUI

/// Face ID 잠금과 금액 가리기.
///
/// 이 앱은 화면 하나에 가족 전 재산이 큰 글씨로 떠 있다. 지하철에서 열면
/// 옆 사람이 다 본다. 두 가지를 따로 둔 이유는 목적이 다르기 때문이다 —
/// **잠금은 남이 내 폰을 여는 것**을, **가리기는 어깨 너머를** 막는다.
///
/// 인증이 계속 실패해 한 번 크게 고쳤다 (docs/08-feedback.md 4번).
/// 그때 배운 것 셋:
///  · `NSFaceIDUsageDescription` 이 없으면 **평가 자체가 실패한다** (project.yml)
///  · 인증 창이 뜨면 앱은 `.inactive` 가 된다. 그때 잠그면 **스스로 판을 엎는다**
///    (`SlowRichApp` 은 `.background` 에서만 잠근다)
///  · 사용자가 취소한 것은 오류가 아니다. 빨간 글씨로 띄울 일이 아니다
@Observable
@MainActor
final class AppLock {
    static let shared = AppLock()

    /// 인증을 통과했는가. 앱이 백그라운드로 가면 다시 false 가 된다.
    var isUnlocked = false

    /// 사람이 읽을 실패 사유. **취소했을 때는 nil 이다.**
    var lastError: String?

    /// 생체 인증도 기기 암호도 쓸 수 없는 상태인가.
    /// 이 값이 true 면 화면이 탈출구를 보여준다 — 안 그러면 자기 기록에서 잠긴다.
    var isLockedOut = false

    private var isAuthenticating = false

    private init() {
        // 잠금을 안 켰으면 처음부터 열린 상태다.
        isUnlocked = !AppLock.isEnabled
    }

    static let enabledKey = "security.appLock"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 이 기기가 본인 확인을 할 수 있는가. 생체 인증이 없어도 기기 암호가 있으면 true 다.
    static var isBiometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "기기 잠금"
        }
    }

    func lock() {
        guard AppLock.isEnabled else { return }
        isUnlocked = false
        lastError = nil
    }

    func unlock() async {
        guard AppLock.isEnabled else {
            isUnlocked = true
            return
        }
        // 화면이 뜨자마자 한 번, 버튼으로 또 한 번 — 겹쳐 부르면 시스템이
        // 앞의 평가를 취소하고 그 취소가 오류로 보인다.
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        // 여기서 막히면 인증할 방법이 아예 없는 것이다. 기기 암호조차 없는 상태다.
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else {
            isLockedOut = true
            lastError = AppLock.message(for: probe)
            return
        }
        isLockedOut = false

        do {
            // deviceOwnerAuthentication 은 생체 인증이 실패해도 암호로 넘어간다.
            // 생체만 쓰면 마스크·장갑 같은 상황에서 앱이 통째로 막힌다.
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "가족 자산 기록을 열려면 인증이 필요합니다"
            )
            lastError = nil
        } catch {
            isUnlocked = false
            lastError = AppLock.message(for: error as NSError)
        }
    }

    /// 인증할 방법이 없을 때 잠금을 끄고 들어간다.
    ///
    /// 기기 암호조차 설정돼 있지 않은 상태에서만 화면이 이 길을 보여준다.
    /// 그런 기기는 어차피 아무나 열 수 있으므로 이 잠금이 지키는 것이 없다.
    /// **자기 기록에서 잠기는 상태를 남겨 두지 않는 것**이 더 중요하다.
    func disableLockAndEnter() {
        UserDefaults.standard.set(false, forKey: AppLock.enabledKey)
        isLockedOut = false
        lastError = nil
        isUnlocked = true
    }

    /// `NSError` 를 그대로 보여주면 `com.apple.LocalAuthentication 오류 -6` 같은
    /// 말이 사용자에게 간다. 사람이 읽을 문장으로 옮기고, **취소는 오류가 아니므로
    /// nil 을 돌려준다.**
    static func message(for error: NSError?) -> String? {
        guard let code = (error?.code).flatMap(LAError.Code.init(rawValue:)) else {
            return error?.localizedDescription
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return nil
        case .userFallback:
            return nil
        case .biometryNotEnrolled:
            return "\(biometryLabel) 가 등록돼 있지 않습니다. 기기 암호로 열 수 있습니다."
        case .biometryLockout:
            return "여러 번 실패해 잠겼습니다. 기기 암호를 한 번 입력하면 풀립니다."
        case .passcodeNotSet:
            return "기기에 암호가 설정돼 있지 않아 본인 확인을 할 수 없습니다."
        case .biometryNotAvailable:
            return "\(biometryLabel) 를 쓸 수 없습니다. 설정 → 느린 부자의 기록 에서 권한을 확인해 주세요."
        case .authenticationFailed:
            return "확인하지 못했습니다. 다시 시도해 주세요."
        default:
            return "인증에 실패했습니다. 다시 시도해 주세요."
        }
    }
}

/// 금액 가리기. 켜면 모든 금액이 `••••` 로 바뀐다.
///
/// 잠금과 달리 인증이 필요 없다 — 어깨 너머를 막는 것이 목적이므로
/// 한 번 탭으로 켜고 끌 수 있어야 한다.
enum AmountPrivacy {
    static let key = "security.hideAmounts"

    static var isHidden: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// 가려진 상태면 자릿수만 남긴 점을 돌려준다.
    /// 길이를 원본에 맞추면 "얼마쯤인지"가 그대로 새어 나가므로 고정 길이로 둔다.
    static func mask(_ text: String) -> String {
        isHidden ? "••••" : text
    }
}
