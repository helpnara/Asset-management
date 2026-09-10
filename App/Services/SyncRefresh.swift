import Foundation

/// **당겨서 새로고침이 하는 일** (docs/08-feedback.md 73번).
///
/// iCloud 에 "지금 가져와" 라고 명령할 공개 API 는 없다 — 가져오기는 조용한
/// 푸시와 앱이 앞으로 올 때 저절로 돈다. 그래서 당기는 동작은 정직하게 할 수
/// 있는 셋만 한다: 모아 둔 변경을 그 자리에서 저장해 **내보내기를 바로 시작**
/// 시키고, 역할·참가자·잔여 기록 같은 **상태를 다시 읽고**, 마지막 가져오기·
/// 내보내기가 **몇 초 전**인지 알려 준다. "동기화 중" 이라고 말하지 않는다.
@MainActor
enum SyncRefresh {

    static func run() async -> String {
        Autosave.shared.flush()
        FamilySharing.shared.refreshState()
        // 상태 재판정은 백그라운드라 한 박자 걸린다. 스피너가 그 시간을 보여 준다.
        try? await Task.sleep(for: .milliseconds(1_200))
        return note()
    }

    /// "마지막 가져오기 12초 전 · 내보내기 3초 전". 로컬 저장소면 그렇다고 적는다.
    static func note() -> String {
        guard Persistence.mode == .cloudKit else { return "이 기기에만 저장합니다 · 상태를 다시 읽었습니다" }
        let monitor = CloudKitSyncMonitor.shared
        func age(_ attempt: CloudKitSyncMonitor.Attempt?) -> String {
            guard let attempt else { return "아직 없음" }
            let seconds = max(0, Int(Date.now.timeIntervalSince(attempt.endedAt)))
            let when: String
            if seconds < 60 { when = "\(seconds)초 전" }
            else if seconds < 3_600 { when = "\(seconds / 60)분 전" }
            else { when = "\(seconds / 3_600)시간 전" }
            return attempt.succeeded ? when : "\(when) 실패"
        }
        return "마지막 가져오기 \(age(monitor.lastImport)) · 내보내기 \(age(monitor.lastExport))"
    }
}
