import CloudKit
import CoreData
import Foundation

/// iCloud 동기화가 **실제로 되고 있는지** 지켜본다.
///
/// **왜 필요한가.** 그전까지 `더보기 → 동기화` 는 저장소가 어떤 모드로 열렸는지와
/// iCloud 계정이 붙었는지만 보여 줬다. 그런데 그 둘이 다 초록이어도 **밀어 넣기가
/// 전부 실패하고 있을 수 있다** — CloudKit Production 스키마에 레코드 타입이
/// 없으면 그렇게 된다. 앱은 로컬에 잘 저장하니 화면에서는 멀쩡해 보인다.
///
/// 이것이 이 앱에서 제일 위험한 상태다. "몇 달치가 백업되고 있는 줄 알았는데
/// 아니었다" 는 되돌릴 방법이 없다. 그래서 **마지막 내보내기가 성공했는지**를
/// 직접 본다.
///
/// SwiftData 는 속으로 `NSPersistentCloudKitContainer` 를 쓰므로 그것이 쏘는
/// 알림을 그대로 받을 수 있다.
@MainActor
@Observable
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    /// 한 번의 동기화 시도 결과. `@Model` 이 아니라 값이라 안전하게 옮길 수 있다.
    struct Attempt: Sendable, Equatable {
        var kind: Kind
        var endedAt: Date
        var succeeded: Bool
        /// 실패 이유. 스키마가 없으면 여기에 그렇게 적힌다.
        var failure: String?

        enum Kind: String, Sendable {
            case setup, importing, exporting

            var label: String {
                switch self {
                case .setup: return "준비"
                case .importing: return "가져오기"
                case .exporting: return "내보내기"
                }
            }
        }
    }

    private(set) var lastImport: Attempt?
    private(set) var lastExport: Attempt?
    private(set) var lastSetup: Attempt?
    private var observer: NSObjectProtocol?

    private init() {}

    /// 알림을 듣기 시작한다. 앱이 뜰 때 한 번 부른다.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // `Event` 는 Sendable 이 아니다. 값만 뽑아서 넘긴다 —
            // `@Model` 을 async 경계 너머로 넘기지 않는 것과 같은 이유다.
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            // 끝나지 않은 이벤트는 아직 결과가 없다.
            guard let endedAt = event.endDate else { return }

            let kind: Attempt.Kind
            switch event.type {
            case .setup: kind = .setup
            case .import: kind = .importing
            case .export: kind = .exporting
            @unknown default: return
            }

            let attempt = Attempt(
                kind: kind,
                endedAt: endedAt,
                succeeded: event.succeeded,
                failure: event.error.map { Self.describe($0) }
            )
            MainActor.assumeIsolated { self?.record(attempt) }
        }
    }

    private func record(_ attempt: Attempt) {
        switch attempt.kind {
        case .setup: lastSetup = attempt
        case .importing: lastImport = attempt
        case .exporting: lastExport = attempt
        }
    }

    /// 사람이 읽을 수 있게 줄인다. **스키마가 없는 경우를 콕 집어 알려 준다** —
    /// 이 앱에서 실제로 마주칠 가능성이 가장 큰 실패이기 때문이다.
    static func describe(_ error: Error) -> String {
        let ck = error as? CKError
            ?? (error as NSError).userInfo[NSUnderlyingErrorKey] as? CKError
        if let ck {
            switch ck.code {
            case .invalidArguments:
                // "Cannot create new type ... in production schema"
                return "CloudKit Production 스키마에 레코드 타입이 없습니다. 스키마를 배포해야 합니다. (\(ck.localizedDescription))"
            case .notAuthenticated:
                return "iCloud에 로그인되어 있지 않습니다."
            case .quotaExceeded:
                return "iCloud 저장 공간이 부족합니다."
            case .networkUnavailable, .networkFailure:
                return "네트워크에 연결되지 않았습니다."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
