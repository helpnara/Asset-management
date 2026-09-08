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

    /// **서버에 진짜로 저장된 공유.** 없으면 `nil`.
    ///
    /// `url` 이 있으면 서버에 있다 — CloudKit 이 저장하면서 붙여 주는 값이라
    /// **반쪽짜리와 진짜를 가르는 유일한 기준**이다. 첫 시도에서 로컬에만
    /// 만들어진 공유는 `url` 이 없다.
    ///
    /// 이 구분을 몰라서 한동안 두 갈래를 하나로 합쳐 두었고, 그 바람에
    /// **관리 화면이 통째로 사라졌다.** 갈래를 없앨 것이 아니라 가르는
    /// 기준을 찾았어야 했다.
    func savedShare(for household: Household) -> CKShare? {
        guard let share = existingShare(for: household), share.url != nil else { return nil }
        return share
    }

    /// 로컬에 있는 공유. 반쪽짜리도 포함한다.
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

        // **이미 있는 공유도 여기를 지나가게 한다.** 처음에는 "이미 있으면
        // `init(share:container:)` 로" 라고 갈랐는데, 첫 시도에서 공유가
        // 로컬에만 만들어지면 그 반쪽짜리가 골라져 고친 길을 안 지나간다.
        let existing = existingShare(for: household)

        // `completion` 도 `CKShare` 도 `Sendable` 이 아니다. 안전한 이유를
        // 아는 상자에 담아 건넨다.
        let box = UncheckedBox(completion)
        let state = PreparationState()

        // **빈 화면을 영원히 두지 않는다.**
        //
        // 준비가 끝날 때까지 시트는 비어 있다. 저쪽이 아무 말도 안 하면
        // 사용자는 흰 화면만 보고 무엇이 잘못됐는지 알 방법이 없다.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            guard !state.finished else { return }
            state.finished = true
            self.lastFailure = "공유 만들기: 25초 안에 끝나지 않았습니다.\n"
                + "더보기 → 동기화의 마지막 내보내기가 실패 중이면 "
                + "성공으로 돌아온 뒤 다시 시도하세요."
            box.value(nil, nil, FamilySharingFailure.timedOut)
        }

        // **이 블록은 메인이라는 보장이 없다.**
        //
        // Core Data 가 백그라운드에서 부른다. 여기서 `MainActor.assumeIsolated`
        // 를 쓰면 **그 자리에서 앱이 죽는다** — 실제로 공유 대상을 누르는
        // 순간(= 저장이 일어나는 순간) 죽었다.
        //
        // `CloudKitSyncMonitor` 가 같은 모양으로 멀쩡한 것은 그쪽 옵저버가
        // `queue: .main` 으로 등록돼 **메인이 보장되기 때문**이다. 그 보장
        // 없이 모양만 베끼면 이렇게 된다.
        //
        // `CKShare` 는 `Sendable` 이 아니라 `Task` 로 못 넘긴다. 상자에 담아
        // 메인 큐로 건너간 뒤, **거기서는 정말 메인이므로** `assumeIsolated`
        // 가 옳다.
        cloudContainer.share([household], to: existing) { _, share, container, error in
            let carried = UncheckedBox((share, container, error))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !state.finished else { return }   // 시간 초과로 이미 끝냈다
                    state.finished = true
                    let (share, container, error) = carried.value
                    if let error {
                        self.record(error, while: "공유 만들기")
                    }
                    // 상대가 초대 화면에서 보는 이름. **넘기기 전에** 얹는다 —
                    // 넘긴 뒤에 고치면 UIKit 이 저장한 것과 어긋난다.
                    if let share {
                        share[CKShare.SystemFieldKey.title] = title
                    }
                    box.value(share, container, error)
                }
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
        let controller = makeController(titled: title)
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

    /// **저장된 공유가 있으면 관리 화면, 없으면 만들기.**
    ///
    /// 두 화면은 하는 일이 다르다. 관리 쪽은 참가자 목록·권한·공유 중단을
    /// 내놓고, 만들기 쪽은 초대 링크를 보낼 곳을 고르게 한다. 하나로 합치면
    /// 관리할 방법이 없어진다.
    ///
    /// 가르는 기준은 `share.url` 이다 — 서버에 저장돼야 생기는 값이라
    /// 반쪽짜리를 관리 화면으로 보내는 일이 없다.
    private static func makeController(titled title: String) -> UICloudSharingController {
        let household = Household.current(in: Persistence.viewContext)
        if let saved = FamilySharing.shared.savedShare(for: household) {
            return UICloudSharingController(
                share: saved,
                container: CKContainer(identifier: Persistence.cloudKitContainerID))
        }
        return UICloudSharingController { _, completion in
            FamilySharing.shared.prepareShare(titled: title, completion: completion)
        }
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
        /// **이 콜백들도 메인이라는 보장이 없다.** 공유 저장은 네트워크
        /// 작업이라 백그라운드에서 온다. 오류를 **여기서 미리 글로 바꿔**
        /// 놓으면 건너가는 것이 문자열뿐이라 안전하다.
        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            let text = CloudKitErrorText.describe(error)
            Task { @MainActor in
                FamilySharing.shared.lastFailure = "시트가 공유를 저장\n" + text
            }
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Task { @MainActor in FamilySharing.shared.lastFailure = nil }
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            Task { @MainActor in FamilySharing.shared.lastFailure = nil }
        }
    }
}
