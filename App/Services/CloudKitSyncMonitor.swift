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
/// 저장 계층이 `NSPersistentCloudKitContainer` 이므로 그것이 쏘는
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

    /// **최근 시도 전부** (최근 것이 앞). 마지막 한 번만 들고 있으면 실패 뒤에
    /// 다른 기록이 성공했을 때 **실패가 지워진다** (165번) — "마지막 내보내기:
    /// 성공" 인 채로 계획 한 건이 영영 안 올라가고 있었다. 실패한 시도의
    /// 이유(어느 레코드 타입이 왜)가 이 앱에서 유일한 단서다.
    private(set) var history: [Attempt] = []
    private static let historyLimit = 30

    var recentFailures: [Attempt] { history.filter { !$0.succeeded } }

    /// 이 실패 **뒤에** 같은 종류가 성공한 시각 (193번 A). 일시 오류는 저장 계층이
    /// 다시 보내 곧 성공하는데, 실패만 남아 있으면 고장처럼 읽힌다. 다만 뒤의 성공이
    /// 실패한 기록을 실어 갔다는 보장은 없어서(165번) **"풀렸다" 가 아니라 "그 뒤
    /// 성공" 이라고만** 적는다.
    func successAfter(_ failure: Attempt) -> Date? {
        history.filter { $0.kind == failure.kind && $0.succeeded && $0.endedAt > failure.endedAt }
            .map(\.endedAt).min()
    }

    /// 지금 돌고 있는 가져오기 수. 저장소마다 따로 도니 둘일 수 있다.
    /// 빈 화면이 "아직 없는 것" 인지 "아직 안 온 것" 인지 가르는 근거다
    /// (docs/08-feedback.md 53번).
    private(set) var importsInFlight = 0
    /// 이번 실행에서 가져오기가 한 번이라도 끝났는가. 끝나기 전의 빈 화면은
    /// "받아오는 중" 으로 본다.
    private(set) var hasFinishedImport = false

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
            // 관리 객체를 async 경계 너머로 넘기지 않는 것과 같은 이유다.
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            let kind: Attempt.Kind
            switch event.type {
            case .setup: kind = .setup
            case .import: kind = .importing
            case .export: kind = .exporting
            @unknown default: return
            }

            // 끝나지 않은 이벤트는 아직 결과가 없다 — 대신 "시작됐다" 는 것을 센다.
            guard let endedAt = event.endDate else {
                if kind == .importing {
                    MainActor.assumeIsolated { self?.importsInFlight += 1 }
                }
                return
            }

            let attempt = Attempt(
                kind: kind,
                endedAt: endedAt,
                succeeded: event.succeeded,
                failure: event.error.map { Self.describe($0) }
            )
            MainActor.assumeIsolated { self?.record(attempt) }
        }
        watchForNothingToImport()
    }

    /// iCloud 계정이 없는가 — 그러면 동기화도 받아올 것도 없다 (194번 U1).
    private(set) var hasNoAccount = false

    /// **받아올 것이 없으면 기다리지 않는다** (194번 U1).
    ///
    /// "받아오기 끝남" 은 가져오기가 한 번 끝나야만 켜졌다. 그런데 iCloud 에 로그인하지
    /// 않은 기기는 가져오기가 아예 안 돈다 — 빈 상태의 시작 단추가 "iCloud 에서 받아오는
    /// 중" 안내로 바뀐 채 돌아오지 않았다. 계정이 없으면 바로 끝난 것으로 보고, 계정이
    /// 있어도 30초 동안 가져오기 소식이 하나도 없으면 끝난 것으로 본다. 소식이 한 번이라도
    /// 왔으면(돌고 있으면) 그 결과를 기다린다. CI 처럼 iCloud 없이 연 저장소는 묻지 않는다
    /// — 자격 없이 `CKContainer` 를 만들면 앱이 죽는다.
    private func watchForNothingToImport() {
        guard Persistence.mode == .cloudKit else { return }
        Task { @MainActor [weak self] in
            let status = try? await CKContainer(identifier: Persistence.cloudKitContainerID).accountStatus()
            // 확실히 없을 때만 바로 끝낸다. "잠깐 확인 불가" 는 아래 30초를 기다린다.
            if status == .noAccount || status == .restricted, let self {
                self.hasNoAccount = true
                self.hasFinishedImport = true
                return
            }
            try? await Task.sleep(for: .seconds(30))
            guard let self, !self.hasFinishedImport, self.importsInFlight == 0, self.lastImport == nil else { return }
            self.hasFinishedImport = true
        }
    }

    private func record(_ attempt: Attempt) {
        history.insert(attempt, at: 0)
        if history.count > Self.historyLimit { history.removeLast() }
        switch attempt.kind {
        case .setup: lastSetup = attempt
        case .importing:
            lastImport = attempt
            importsInFlight = max(importsInFlight - 1, 0)
            hasFinishedImport = true
        case .exporting: lastExport = attempt
        }
    }

    /// 사람이 읽을 수 있게 줄인다. **스키마가 없는 경우를 콕 집어 알려 준다** —
    /// 이 앱에서 실제로 마주칠 가능성이 가장 큰 실패이기 때문이다.
    static func describe(_ error: Error) -> String {
        CloudKitErrorText.describe(error)
    }
}
