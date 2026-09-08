import CloudKit
import CoreData
import SwiftUI
import UIKit

/// `FamilySharing` **밖에** 둔다. 그 클래스는 `@MainActor` 인데
/// `LocalizedError` 의 `errorDescription` 은 격리되지 않은 요구라,
/// 안에 넣으면 준수가 막힌다.
enum FamilySharingFailure: LocalizedError {
    case noCloudKit
    case noShare
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noCloudKit:
            return "iCloud 로 열리지 않아 공유할 수 없습니다. 더보기 → 동기화를 보세요."
        case .noShare:
            return "공유를 만들지 못했습니다."
        case .timedOut:
            return "공유를 만드는 데 너무 오래 걸립니다. 더보기 → 동기화의 "
                + "**마지막 내보내기**가 성공으로 돌아온 뒤 다시 시도하세요."
        }
    }
}

/// **가족 공유.** 가구 하나 = `CKShare` 한 장 (docs/09-family-sharing.md 2b).
///
/// `CKShare` 는 **한 장에 권한이 하나**다. 구성원마다 다른 권한을 주려면 공유를
/// 여러 장 만들어야 하는데, 그러면 자료를 어느 장에 매달지부터 갈라진다.
/// 그래서 **공유는 한 장으로 두고 역할은 앱 안에서 판정한다.**
///
/// **실패는 시트가 알린다.** 우리가 따로 문구를 만들지 않는다 — 참가자
/// 추가·링크 생성이 막히면 `UICloudSharingController` 가 그 자리에서
/// 알림을 띄운다. 실제로 그 알림이 이번 버그를 알려 줬다.
@MainActor
@Observable
final class FamilySharing {

    static let shared = FamilySharing()

    /// **공유가 왜 안 됐나.** 시트가 띄우는 알림은 "링크를 생성할 수
    /// 없습니다" 까지만 말하고 CloudKit 오류 코드를 안 보여 준다. 그 코드가
    /// 없으면 원인을 추측하게 되고, 오늘 그것으로 한 바퀴를 버렸다.
    ///
    /// 저장소를 못 열었을 때 이유를 화면에 내놓아 답을 얻은 것과 같은 수법이다.
    var lastFailure: String?

    private init() {}

    /// 오류를 **가장 안쪽 이유까지** 펴서 적는다 (`CloudKitErrorText`).
    func record(_ error: Error, while step: String) {
        lastFailure = "\(step)\n" + CloudKitErrorText.describe(error)
    }

    private var cloudContainer: NSPersistentCloudKitContainer? {
        Persistence.container as? NSPersistentCloudKitContainer
    }

    /// 이미 만들어 둔 공유. 없으면 `nil`.
    ///
    /// 두 번 만들면 안 된다 — 자료가 어느 쪽에 매달렸는지가 갈린다.
    /// 그래서 만들기 전에 항상 여기부터 본다.
    func existingShare(for household: Household) -> CKShare? {
        guard let cloudContainer else { return nil }
        return try? cloudContainer
            .fetchShares(matching: [household.objectID])[household.objectID]
    }

    /// **초대 시트가 공유를 만들 때 부르는 자리.**
    ///
    /// 처음에는 우리가 먼저 공유를 만들고 `UICloudSharingController(share:container:)`
    /// 로 넘겼는데, 기기에서 이렇게 막혔다:
    ///
    ///     사람을 추가할 수 없음 — 공유를 위한 링크를 생성할 수 없습니다.
    ///
    /// 그 초기화 함수는 **이미 서버에 저장된 공유**를 요구한다. 게다가 우리는
    /// 만든 **뒤에** 제목을 덧쓰고 저장하지 않아서, 서버본과 어긋난 것을
    /// 넘기고 있었다. 시트는 열리고 참가자를 더하는 순간 저장이 막힌다.
    ///
    /// 애플이 Core Data 용으로 문서화한 길은 `preparationHandler` 다 —
    /// **UIKit 이 공유를 만들고 저장까지 맡는다.** 우리는 뿌리 객체를 넘기고
    /// 제목만 얹는다.
    func prepareShare(titled title: String,
                      completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
        guard let cloudContainer else {
            completion(nil, nil, FamilySharingFailure.noCloudKit)
            return
        }

        lastFailure = nil

        // 뿌리가 없으면 만든다. **저장 안 된 객체는 공유할 수 없으므로**
        // 만든 직후 바로 쓴다.
        let household = Household.current(in: Persistence.viewContext)
        Autosave.shared.flush()

        // **이미 있는 공유도 여기를 지나가게 한다.**
        //
        // 처음에는 "이미 있으면 `init(share:container:)` 로" 라고 두었는데,
        // 그것이 두 번째 실패를 만들었다. 첫 시도에서 공유가 **로컬에만**
        // 만들어지고 서버 저장이 실패하면, 다음부터 그 반쪽짜리를 찾아내
        // **고친 길을 아예 안 지나간다.** 겉으로는 같은 오류가 반복된다.
        //
        // `share(_:to:)` 에 그것을 넘기면 그 공유를 이어서 쓰고, 저장은
        // UIKit 이 맡는다. 반쪽으로 남아 있어도 여기서 아물어진다.
        let existing = existingShare(for: household)

        // `completion` 은 `Sendable` 이 아닌데 아래 블록은 `@Sendable` 이다.
        // 그대로 잡으면 "sending 'completion' risks causing data races" 로 막힌다.
        // **실제로는 안전하다** — 블록도 여기도 전부 메인에서 돈다. 그 사실을
        // 아는 상자에 담아 건넨다 (`Persistence.ModelBox` 와 같은 수법).
        let box = UncheckedBox(completion)
        // `self` 는 메인 액터다. 아래 블록도 메인에서 돈다.
        cloudContainer.share([household], to: existing) { _, share, container, error in
            MainActor.assumeIsolated {
                // 상대가 초대 화면에서 보는 이름. **넘기기 전에** 얹는다 —
                // 넘긴 뒤에 고치면 UIKit 이 저장한 것과 어긋난다.
                if let error {
                    self.record(error, while: "공유 만들기")
                }
                if let share {
                    share[CKShare.SystemFieldKey.title] = title
                }
                box.value(share, container, error)
            }
        }
    }

    /// **이 기기가 이 객체를 고칠 수 있나.**
    ///
    /// 참가자 쪽에서는 `CKShare` 의 권한이 답한다. 소유자 쪽에서는 늘 참이다.
    /// 4단계에서 `\.canEdit` 에 꽂을 값이 이것이다 — 화면은 이미 그 환경값
    /// 하나만 읽게 해 두었다 (08-feedback 48번).
    func canEdit(_ object: NSManagedObject) -> Bool {
        guard let cloudContainer else { return true }
        return cloudContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}

/// `@Sendable` 클로저 안으로 격리되지 않은 값을 들고 들어가기 위한 상자.
///
/// 검사를 끄는 것이 아니라 **안전한 이유를 아는 자리**를 만드는 것이다:
/// 담긴 클로저를 부르는 곳도 만드는 곳도 전부 메인 액터다.
/// 준비가 끝났는지. 시간 초과와 진짜 응답이 **둘 다** 완료를 부르면 안 된다.
private final class PreparationState: @unchecked Sendable {
    var finished = false
}

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// **초대 시트를 UIKit 으로 직접 띄운다.**
///
/// 처음에는 `UIViewControllerRepresentable` 로 감싸 SwiftUI `.sheet` 안에
/// 박아 넣었는데, 기기에서 **빈 화면**이 나왔다.
///
/// `preparationHandler` 로 만든 `UICloudSharingController` 는 준비가 끝날
/// 때까지 비어 있고, **그 준비는 컨트롤러가 제대로 모달로 표시될 때
/// 시작된다.** 남의 뷰 안에 박아 넣으면 그 생애주기를 못 타서 준비가
/// 시작되지 않는다 — 그래서 영영 빈 화면이다.
///
/// (빌드 28·29 에서 시트가 그려졌던 것은 `init(share:container:)` 라
/// 준비 없이 즉시 그려졌기 때문이다. 준비 핸들러로 바꾸자 드러났다.)
///
/// 참가자 추가·권한 변경·공유 중단이 다 이 화면에 붙어 있으므로 우리가
/// 다시 만들지 않는다. 띄우는 방식만 애플이 기대하는 대로 고친다.
@MainActor
enum FamilyShareSheet {

    static func present(titled title: String) {
        let controller = UICloudSharingController { _, completion in
            FamilySharing.shared.prepareShare(titled: title, completion: completion)
        }
        // 보기 전용이 **기본**이다 (확정된 요구). 넓히는 것은 이 화면에서
        // 아빠가 참가자별로 정한다.
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        controller.delegate = delegate
        delegate.title = title

        guard let top = topViewController() else {
            FamilySharing.shared.lastFailure = "초대 화면을 띄울 자리를 찾지 못했습니다."
            return
        }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }

    /// 지금 화면 맨 위. 시트 위에 시트를 띄우면 아무것도 안 보인다.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// 대리자는 **한 번 만들어 들고 있는다.** 지역 변수로 두면 시트가 뜬
    /// 직후 사라져서, 실패 이유를 받을 자리가 없어진다.
    private static let delegate = Delegate()

    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        var title = ""

        func itemTitle(for controller: UICloudSharingController) -> String? { title }

        /// **시트가 실패한 이유를 여기서 붙잡는다.** 시트의 알림은 "링크를
        /// 생성할 수 없습니다" 까지만 말한다. CloudKit 오류 코드는 이
        /// 콜백으로만 온다.
        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            MainActor.assumeIsolated {
                FamilySharing.shared.record(error, while: "시트가 공유를 저장")
            }
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            MainActor.assumeIsolated { FamilySharing.shared.lastFailure = nil }
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            MainActor.assumeIsolated { FamilySharing.shared.lastFailure = nil }
        }
    }
}
