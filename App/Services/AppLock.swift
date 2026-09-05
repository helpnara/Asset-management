import LocalAuthentication
import Observation
import SwiftUI

/// Face ID 잠금과 금액 가리기.
///
/// 이 앱은 화면 하나에 가족 전 재산이 큰 글씨로 떠 있다. 지하철에서 열면
/// 옆 사람이 다 본다. 두 가지를 따로 둔 이유는 목적이 다르기 때문이다 —
/// **잠금은 남이 내 폰을 여는 것**을, **가리기는 어깨 너머를** 막는다.
@Observable
@MainActor
final class AppLock {
    static let shared = AppLock()

    /// 인증을 통과했는가. 앱이 백그라운드로 가면 다시 false 가 된다.
    var isUnlocked = false
    var lastError: String?

    private init() {
        // 잠금을 안 켰으면 처음부터 열린 상태다.
        isUnlocked = !AppLock.isEnabled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "security.appLock")
    }

    /// 이 기기가 생체 인증을 지원하는가. 시뮬레이터·미등록 기기에서는 false 다.
    static var isBiometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
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
    }

    func unlock() async {
        guard AppLock.isEnabled else {
            isUnlocked = true
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "취소"
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
            lastError = (error as? LAError)?.localizedDescription ?? error.localizedDescription
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
