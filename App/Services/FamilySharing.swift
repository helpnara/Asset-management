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

/// 공유가 지금 어떤 상태인가. **값이라 스레드를 넘겨도 안전하다.**
struct FamilyShareState: Sendable {
    var households = 0
    var hasLocalShare = false
    var isSaved = false
    var participants = 0

    /// **이 기기의 진짜 역할.** 공유 저장소에 `CKShare` 가 있으면 참가자고,
    /// 그 공유의 `currentUserParticipant.permission` 이 역할을 정한다
    /// (docs/09-family-sharing.md 4단계). 없으면 소유자다.
    var role: FamilyRole = .owner

    var isParticipant: Bool { role != .owner }

    /// 사람이 읽을 한 줄.
    var label: String {
        if isParticipant { return "참가 중 · \(role.label)" }
        if households == 0 { return "아직 없음" }
        if !hasLocalShare { return "공유 안 함" }
        if !isSaved { return "만들다 만 상태" }
        return "공유 중 · 참가자 \(participants)명"
    }

    var isTrouble: Bool { households > 1 || (hasLocalShare && !isSaved) }
}

/// **가족 공유.** 가구 하나 = `CKShare` 한 장 (docs/09-family-sharing.md 2b).
///
/// `CKShare` 는 **한 장에 권한이 하나**다. 구성원마다 다른 권한을 주려면 공유를
/// 여러 장 만들어야 하는데, 그러면 자료를 어느 장에 매달지부터 갈라진다.
/// 그래서 **공유는 한 장으로 두고 역할은 앱 안에서 판정한다.**
///
/// ## ⚠️ `share(_:to:)` 를 메인에서 부르면 앱이 죽는다
///
/// 기기 크래시 로그가 알려 줬다:
///
///     FRONTBOARD 0x8BADF00D — scene-update watchdog transgression:
///     exhausted real (wall clock) time allowance of 10.00 seconds
///
///     Thread 0 (com.apple.main-thread):
///       _dispatch_group_wait_slow
///       -[_PFRequestExecutor wait]
///       -[NSPersistentCloudKitContainer shareManagedObjects:toShare:completion:]
///       -[UICloudSharingController __viewControllerWillBePresented:]
///
/// **`share(_:to:)` 는 완료 블록을 받으면서도 부른 스레드를 붙잡고 기다린다.**
/// 그런데 `UICloudSharingController` 는 준비 핸들러를 **메인에서** 부른다.
/// 옮길 레코드가 수백 건이면 10초를 넘고, 워치독이 앱을 죽인다.
///
/// 그래서 여기서는 **백그라운드 컨텍스트에서** 부른다. 관리 객체는 스레드를
/// 넘기지 않고 `objectID` 만 넘겨 그쪽에서 다시 꺼낸다 (CLAUDE.md).
///
/// `fetchShares` 도 같은 실행기를 쓰므로 상태를 읽는 것도 메인에서 안 한다.
@MainActor
@Observable
final class FamilySharing {

    static let shared = FamilySharing()

    /// **공유가 왜 안 됐나.** 시트가 띄우는 알림은 CloudKit 오류 코드를 안
    /// 보여 준다. 그 코드가 없으면 원인을 추측하게 된다.
    var lastFailure: String?

    /// 화면이 읽는 상태. 백그라운드에서 읽어 여기에 얹는다.
    private(set) var state = FamilyShareState()

    /// 마지막으로 판정한 역할. **앱을 켜자마자** 화면이 맞는 역할로 뜨게 한다 —
    /// 공유 조회는 백그라운드라 한 박자 늦는데, 그 사이 참가자 기기에
    /// 편집 버튼이 잠깐 보였다 사라지면 고장으로 읽힌다.
    static let roleKey = "family.resolvedRole"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.roleKey),
           let role = FamilyRole(rawValue: raw) {
            state.role = role
        }
    }

    /// `CKShare` 참가자 정보를 앱의 역할로 옮긴다. 백그라운드에서 부른다.
    nonisolated static func role(of share: CKShare) -> FamilyRole {
        guard let me = share.currentUserParticipant else { return .viewer }
        if me.role == .owner { return .owner }
        return me.permission == .readWrite ? .editor : .viewer
    }

    private var cloudContainer: NSPersistentCloudKitContainer? {
        Persistence.container as? NSPersistentCloudKitContainer
    }

    /// 오류를 **가장 안쪽 이유까지** 펴서 적는다 (`CloudKitErrorText`).
    func record(_ error: Error, while step: String) {
        lastFailure = "\(step)\n" + CloudKitErrorText.describe(error)
    }

    /// **상태를 백그라운드에서 읽는다.**
    ///
    /// `fetchShares` 도 `share(_:to:)` 와 같은 실행기를 쓴다. 더보기 화면을
    /// 여는 것만으로 메인이 멈추면 안 된다.
    func refreshState() {
        guard let container = cloudContainer else {
            state = FamilyShareState()
            return
        }
        let carried = UncheckedBox((container, Persistence.sharedStore))
        let sharedStoreURL = Persistence.sharedStoreURL
        DispatchQueue.global(qos: .userInitiated).async {
            let (container, sharedStore) = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                var next = FamilyShareState()

                // **참가자인가.** 공유 저장소에 `CKShare` 가 있으면 그렇다.
                // 소유자의 공유는 개인 저장소에 있어서 여기 안 잡힌다.
                if let sharedStore,
                   let share = (try? container.fetchShares(in: sharedStore))?.first {
                    next.role = Self.role(of: share)
                }
                UserDefaults.standard.set(next.role.rawValue, forKey: Self.roleKey)

                // 참가자 기기에는 가구가 **하나만** 있어야 한다. 초대를 받기 전에
                // 앱이 제 가구를 만들어 두므로(첫 화면이 계획을 만든다), 받고
                // 나면 빈 껍데기가 하나 남는다. 그걸 여기서 치운다.
                if next.role != .owner {
                    let pruned = Household.pruneEmptyLocalDuplicates(in: context,
                                                                     sharedStoreURL: sharedStoreURL)
                    if pruned > 0 { try? context.save() }
                }

                let households = (try? context.fetch(Household.fetchRequest())) ?? []
                next.households = households.count
                // 가장 오래된 것이 진짜다 — 나중 것은 뒤늦게 내려온 사본이다.
                if let household = households.min(by: { $0.createdAt < $1.createdAt }),
                   let share = try? container
                       .fetchShares(matching: [household.objectID])[household.objectID] {
                    next.hasLocalShare = true
                    // **`url` 이 있어야 서버에 있는 것이다.** 만들다 만 것과 가른다.
                    next.isSaved = share.url != nil
                    next.participants = share.participants.count
                }
                let result = next
                Task { @MainActor in FamilySharing.shared.state = result }
            }
        }
    }

    /// **초대 시트가 공유를 만들 때 부르는 자리.**
    ///
    /// 애플이 Core Data 용으로 문서화한 길은 `preparationHandler` 다 —
    /// UIKit 이 공유를 만들고 저장까지 맡는다. 우리는 뿌리 객체를 넘기고
    /// 제목만 얹는다. 다만 **부르는 것은 백그라운드에서** 한다 (위 참고).
    func prepareShare(titled title: String,
                      completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
        guard let container = cloudContainer else {
            completion(nil, nil, FamilySharingFailure.noCloudKit)
            return
        }

        lastFailure = nil

        // 뿌리가 없으면 만든다. **저장 안 된 객체는 공유할 수 없으므로**
        // 만든 직후 바로 쓴다. 여기까지는 메인이어야 한다 — viewContext 다.
        let household = Household.current(in: Persistence.viewContext)
        Autosave.shared.flush()
        let rootID = household.objectID

        // `completion` 도 `CKShare` 도 컨테이너도 `Sendable` 이 아니다.
        // 안전한 이유를 아는 상자에 담아 건넨다.
        let box = UncheckedBox(completion)
        let carried = UncheckedBox(container)
        let progress = PreparationState()

        // **빈 화면을 영원히 두지 않는다.** 옮길 것이 많으면 오래 걸리므로
        // 넉넉히 두되, 끝내 안 끝나면 늦었다고 말한다.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            guard !progress.finished else { return }
            progress.finished = true
            self.lastFailure = "공유 만들기: 90초 안에 끝나지 않았습니다.\n"
                + "더보기 → 동기화의 마지막 내보내기가 성공인지 먼저 보세요."
            box.value(nil, nil, FamilySharingFailure.timedOut)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let container = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                guard let root = try? context.existingObject(with: rootID) else {
                    Self.finish(progress, box, nil, nil, FamilySharingFailure.noShare, title)
                    return
                }
                // 이미 있는 공유는 이어서 쓴다. 만들다 만 것도 여기서 아물어진다.
                let existing = try? container.fetchShares(matching: [rootID])[rootID]
                container.share([root], to: existing) { _, share, ckContainer, error in
                    Self.finish(progress, box, share, ckContainer, error, title)
                }
            }
        }
    }

    /// 결과를 **메인으로 건너가서** 한 번만 넘긴다.
    ///
    /// 시간 초과와 진짜 응답이 둘 다 완료를 부르면 안 된다.
    private nonisolated static func finish(_ progress: PreparationState,
                                           _ box: UncheckedBox<(CKShare?, CKContainer?, Error?) -> Void>,
                                           _ share: CKShare?,
                                           _ container: CKContainer?,
                                           _ error: Error?,
                                           _ title: String) {
        let carried = UncheckedBox((share, container, error))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !progress.finished else { return }
                progress.finished = true
                let (share, container, error) = carried.value
                if let error {
                    FamilySharing.shared.record(error, while: "공유 만들기")
                }
                // 상대가 보는 이름. **넘기기 전에** 얹는다.
                if let share {
                    share[CKShare.SystemFieldKey.title] = title
                }
                box.value(share, container, error)
            }
        }
    }

    /// 서버에 저장된 공유. **`state.isSaved` 가 참일 때만 부른다.**
    ///
    /// `fetchShares` 는 메타데이터 조회라 `shareManagedObjects` 처럼 무겁지
    /// 않다 — 앱을 죽인 것은 그쪽이다. 그래도 이미 있다는 것을 알고 부를 때만
    /// 쓴다.
    func savedShare(for household: Household) -> CKShare? {
        guard let cloudContainer,
              let share = try? cloudContainer
                  .fetchShares(matching: [household.objectID])[household.objectID],
              share.url != nil else { return nil }
        return share
    }

    /// **초대를 받아들인다** — 참가자 쪽에서 링크를 눌렀을 때.
    ///
    /// 공유 존을 **공유 저장소**로 들여온다. 개인 저장소를 가리키면 남의
    /// 기록이 내 것에 섞이므로 `Persistence.sharedStore` 여야 한다.
    ///
    /// 이것도 백그라운드에서 부른다. 네트워크 작업이고, 메인을 붙잡는
    /// Core Data 호출에 한 번 데었다 (워치독).
    func accept(_ metadata: CKShare.Metadata) {
        // 소유자가 제 링크를 누르면 서버가 거부한다 (CKError 12, "owner participant
        // tried to accept share"). 서버까지 가지 않고 여기서 말해 준다.
        if metadata.participantRole == .owner {
            lastFailure = "초대 받기: 본인이 만든 공유 링크입니다. 문제없습니다 — "
                + "이 링크는 초대받은 가족의 폰에서 눌러야 합니다."
            return
        }
        guard let container = cloudContainer, let store = Persistence.sharedStore else {
            lastFailure = "초대 받기: iCloud 로 열리지 않아 받을 수 없습니다."
            return
        }
        lastFailure = nil
        let carried = UncheckedBox((container, metadata, store))
        DispatchQueue.global(qos: .userInitiated).async {
            let (container, metadata, store) = carried.value
            container.acceptShareInvitations(from: [metadata], into: store) { _, error in
                let text = error.map { CloudKitErrorText.describe($0) }
                Task { @MainActor in
                    let sharing = FamilySharing.shared
                    if let text {
                        sharing.lastFailure = "초대 받기\n" + text
                    } else {
                        sharing.lastFailure = nil
                        sharing.didAcceptInvitation = true
                    }
                    sharing.refreshState()
                }
            }
        }
    }

    /// 이 기기에서 초대를 받아들인 적이 있나. 참가자 화면의 근거다.
    var didAcceptInvitation = false

    /// **이 기기가 이 객체를 고칠 수 있나.**
    ///
    /// 참가자 쪽에서는 `CKShare` 의 권한이 답한다. 소유자 쪽에서는 늘 참이다.
    /// 4단계에서 `\.canEdit` 에 꽂을 값이 이것이다.
    func canEdit(_ object: NSManagedObject) -> Bool {
        guard let cloudContainer else { return true }
        return cloudContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}

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
        // **저장된 공유가 있다고 화면이 이미 알고 있을 때만** 조회한다.
        // 모르는 채로 물어보면 없는 경우까지 기다리게 된다.
        let household = Household.current(in: Persistence.viewContext)
        if FamilySharing.shared.state.isSaved,
           let saved = FamilySharing.shared.savedShare(for: household) {
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
