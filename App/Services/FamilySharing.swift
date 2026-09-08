import CloudKit
import CoreData
import SwiftUI

/// `FamilySharing` **밖에** 둔다. 그 클래스는 `@MainActor` 인데
/// `LocalizedError` 의 `errorDescription` 은 격리되지 않은 요구라,
/// 안에 넣으면 준수가 막힌다.
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

    /// 오류를 코드까지 펴서 적는다. `CKError` 는 코드가 곧 원인이다.
    func record(_ error: Error, while step: String) {
        let ns = error as NSError
        var lines = ["\(step): \(ns.domain) \(ns.code)"]
        if let reason = ns.localizedFailureReason { lines.append(reason) }
        lines.append(ns.localizedDescription)
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("바탕: \(underlying.domain) \(underlying.code) "
                         + underlying.localizedDescription)
        }
        // CloudKit 이 레코드마다 다른 이유를 줄 때가 있다. 그게 진짜 답이다.
        if let perItem = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for (_, item) in perItem.prefix(3) {
                let e = item as NSError
                lines.append("항목: \(e.domain) \(e.code) \(e.localizedDescription)")
            }
        }
        lastFailure = lines.joined(separator: "\n")
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
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// 애플이 주는 초대 시트. 메시지·메일·링크 복사가 전부 여기 들어 있다.
///
/// **직접 만들지 않는다.** 참가자 추가·권한 변경·공유 중단이 다 이 화면에
/// 붙어 있고, 그것을 우리가 다시 만들면 애플이 고칠 때마다 어긋난다.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let title: String

    /// **길이 하나뿐이다.**
    ///
    /// 처음에는 "이미 있는 공유면 `init(share:container:)`, 없으면 준비 핸들러"
    /// 로 갈랐는데, 그 갈림이 두 번째 실패를 만들었다. 첫 시도에서 공유가
    /// 로컬에만 만들어지고 서버 저장이 실패하면 다음부터 그 반쪽짜리가
    /// 골라져서, **고친 길을 아예 안 지나간다.**
    ///
    /// 준비 핸들러는 이미 있는 공유도 이어서 쓴다. 갈래를 없애는 것이
    /// 갈래마다 옳게 만드는 것보다 낫다.
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            FamilySharing.shared.prepareShare(titled: title, completion: completion)
        }
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

        /// **시트가 실패한 이유를 여기서 붙잡는다.**
        ///
        /// 시트의 알림은 "링크를 생성할 수 없습니다" 까지만 말한다. 진짜 답인
        /// CloudKit 오류 코드는 이 콜백으로만 온다. 화면에 내놓아야 맥 없는
        /// 이 저장소에서 원인을 알 수 있다.
        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            MainActor.assumeIsolated {
                FamilySharing.shared.record(error, while: "시트가 공유를 저장")
            }
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            MainActor.assumeIsolated { FamilySharing.shared.lastFailure = nil }
        }
    }
}
