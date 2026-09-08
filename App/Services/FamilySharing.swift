import CloudKit
import CoreData
import SwiftUI

/// **가족 공유.** 가구 하나 = `CKShare` 한 장 (docs/09-family-sharing.md 2b).
///
/// `CKShare` 는 **한 장에 권한이 하나**다. 구성원마다 다른 권한을 주려면 공유를
/// 여러 장 만들어야 하는데, 그러면 자료를 어느 장에 매달지부터 갈라진다.
/// 그래서 **공유는 한 장으로 두고 역할은 앱 안에서 판정한다.**
/// 초대 시트에 넘길 한 벌. `CKShare` 와 컨테이너가 짝으로 다녀야 한다.
///
/// **`FamilySharing` 안에 중첩하지 않는다.** 그 열거형은 `@MainActor` 라
/// 안에 넣으면 이 타입도 격리되는데, 그러면 격리되지 않은 자리
/// (`UIViewControllerRepresentable` 의 저장 프로퍼티)에서 못 쓴다.
struct FamilyInvite: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// 같은 이유로 밖에 둔다. `LocalizedError` 의 `errorDescription` 은
/// **격리되지 않은** 요구라, `@MainActor` 안에 넣으면 준수가 막힌다.
enum FamilySharingFailure: LocalizedError {
    case noCloudKit
    case noShare

    var errorDescription: String? {
        switch self {
        case .noCloudKit:
            return "iCloud 로 열리지 않아 공유할 수 없습니다. 더보기 → 동기화를 보세요."
        case .noShare:
            return "공유를 만들지 못했습니다."
        }
    }
}

/// **가족 공유.** 가구 하나 = `CKShare` 한 장 (docs/09-family-sharing.md 2b).
///
/// `CKShare` 는 **한 장에 권한이 하나**다. 구성원마다 다른 권한을 주려면 공유를
/// 여러 장 만들어야 하는데, 그러면 자료를 어느 장에 매달지부터 갈라진다.
/// 그래서 **공유는 한 장으로 두고 역할은 앱 안에서 판정한다.**
///
/// **왜 완료 클로저를 안 받나.** 처음에는 `share(_:to:) { ... }` 처럼 부르는
/// 쪽의 클로저를 받았는데 Swift 6 가 막았다:
///
///     sending 'finish' risks causing data races
///
/// `share(_:to:)` 의 완료 블록이 `@Sendable` 이라, 그 안에서 화면의 클로저를
/// 부르면 격리를 건너뛴다. 그래서 **결과를 값으로 들고 있고 화면이 그것을
/// 본다** — `CloudKitSyncMonitor` 와 같은 꼴이다.
@MainActor
@Observable
final class FamilySharing {

    static let shared = FamilySharing()

    /// 만들어진 초대. 화면이 이걸 보고 시트를 띄운다.
    var invite: FamilyInvite?

    /// 실패 이유. 조용히 삼키지 않는다.
    var failure: String?

    private(set) var isWorking = false

    private init() {}

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

    /// 공유를 만들거나, 이미 있으면 그것을 내놓는다.
    func start(for household: Household, titled title: String) {
        guard let cloudContainer else {
            failure = FamilySharingFailure.noCloudKit.localizedDescription
            return
        }

        // **저장 안 된 객체는 공유할 수 없다.** 가구를 방금 만들었다면 아직
        // 디스크에 없다. 모아 둔 것을 여기서 먼저 쓴다.
        Autosave.shared.flush()

        if let existing = existingShare(for: household) {
            invite = FamilyInvite(share: existing,
                                  container: CKContainer(identifier: Persistence.cloudKitContainerID))
            return
        }

        isWorking = true
        failure = nil
        cloudContainer.share([household], to: nil) { [weak self] _, share, container, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isWorking = false
                if let error {
                    self.failure = (error as NSError).localizedDescription
                    return
                }
                guard let share, let container else {
                    self.failure = FamilySharingFailure.noShare.localizedDescription
                    return
                }
                // 상대가 초대 화면에서 보는 이름. 계획 제목을 그대로 쓴다.
                share[CKShare.SystemFieldKey.title] = title
                self.invite = FamilyInvite(share: share, container: container)
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

/// 애플이 주는 초대 시트. 메시지·메일·링크 복사가 전부 여기 들어 있다.
///
/// **직접 만들지 않는다.** 참가자 추가·권한 변경·공유 중단이 다 이 화면에
/// 붙어 있고, 그것을 우리가 다시 만들면 애플이 고칠 때마다 어긋난다.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let invite: FamilyInvite
    let title: String

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: invite.share,
                                                  container: invite.container)
        // 보기 전용이 **기본**이다 (확정된 요구). 넓히는 것은 이 화면에서
        // 아빠가 참가자별로 정한다.
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(title: title) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        init(title: String) { self.title = title }

        func itemTitle(for controller: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            // 조용히 삼키지 않는다 — 이 앱에서 제일 위험한 것이 "된 줄 알았는데
            // 아니었다" 이다. 시트가 알림을 띄우고, 여기서는 로그만 남긴다.
            NSLog("공유를 저장하지 못했습니다: \(error)")
        }
    }
}
