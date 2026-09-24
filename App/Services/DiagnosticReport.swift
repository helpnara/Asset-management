import CloudKit
import Core
import CoreData
import Foundation
import UIKit
import UserNotifications

/// **진단 정보 한 장** (docs/05-roadmap.md G5).
///
/// 서버가 없어서 문제는 스크린샷과 말로만 온다. "동기화가 안 붙어요" 를 풀려면
/// 저장 방식 · iCloud 계정 · 마지막 가져오기/내보내기 · 역할 · 참가자 ID 꼬리 ·
/// 가구 수 · 버전이 필요한데 화면 여섯 개를 돌며 읽어 줘야 했다. 이걸 한 번에
/// 복사해 붙여 넣게 한다. **실제 금액은 안 들어간다** — 건수만.
enum DiagnosticReport {

    @MainActor
    static func build(in context: NSManagedObjectContext) async -> String {
        var lines: [String] = []
        let device = UIDevice.current
        lines.append("느린 부자 \(MoreView.versionText)")
        lines.append("iOS \(device.systemVersion) · \(device.model) · \(Locale.current.identifier) · \(TimeZone.current.identifier)")
        lines.append("찍은 때: \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        // 저장 · 동기화
        switch Persistence.mode {
        case .cloudKit: lines.append("저장: iCloud 동기화")
        case .localOnly(let reason): lines.append("저장: 이 기기에만 — \(reason)")
        case .inMemory: lines.append("저장: 임시 (미리보기)")
        }
        if Persistence.mode != .inMemory {
            let status = try? await CKContainer(identifier: Persistence.cloudKitContainerID).accountStatus()
            lines.append("iCloud 계정: \(accountLabel(status))")
        }
        let monitor = CloudKitSyncMonitor.shared
        lines.append("마지막 준비: \(attempt(monitor.lastSetup))")
        lines.append("마지막 가져오기: \(attempt(monitor.lastImport))")
        lines.append("마지막 내보내기: \(attempt(monitor.lastExport))")
        lines.append("가져오기 끝남: \(monitor.hasFinishedImport ? "예" : "아니오")")
        if let failure = Autosave.shared.lastFailure { lines.append("저장 실패: \(failure)") }
        lines.append("")

        // 가족
        let state = FamilySharing.shared.state
        lines.append("역할: \(state.role.label)\(state.isResolved ? "" : " (아직 확인 중)")\(state.shareLost ? " · 공유 없어짐" : "")")
        lines.append("참가자 ID 꼬리: \(ActorName.idTail(state.participantID))")
        lines.append("이력에 남는 이름: \(ActorName.current)")
        lines.append("공유: \(state.label)")
        lines.append("가구 수: \(Household.count(in: context)) · 뿌리에 안 매달린 기록: \(state.orphans) · 개인 저장소에 남은 가족 기록: \(state.strays)")
        if let blockers = state.pruneBlockers { lines.append("빈 가구 안 치워진 이유: \(blockers)") }
        lines.append("가족 최신 빌드: \(AppUpdate.latestKnownBuild(in: context)) · 이 기기: \(AppUpdate.currentBuild)")
        lines.append("")

        // 기록 (건수만)
        let sessions = context.all(ReviewSession.self)
        lines.append("구성원 \(context.all(Member.self).count) · 계좌 \(context.all(Account.self).count) · 종목 \(context.all(Holding.self).count) · 계획 \(context.all(Plan.self).count)")
        lines.append("점검 \(sessions.filter(\.isComplete).count)주 (기록 \(sessions.count)) · 스냅샷 \(context.all(Snapshot.self).count) · 종목별 값 \(context.all(HoldingRecord.self).count)줄 · 이력 \(context.all(ChangeLog.self).count)줄 · 일기 \(context.all(DiaryEntry.self).count)일")
        if let last = sessions.filter(\.isComplete).max(by: { $0.weekAnchor < $1.weekAnchor }) {
            lines.append("마지막 점검 주: \(last.weekAnchor.formatted(date: .abbreviated, time: .omitted))")
        }
        lines.append("")

        // **동기화 대조** (165번). 두 기기에서 이걸 복사해 나란히 놓으면 어느
        // 엔티티의 어느 묶음이 갈렸는지 바로 보인다. 지문은 내용의 해시라
        // 금액은 안 나간다. 시각은 UTC 가 아니라 이 기기 시간대로 적는다 —
        // 사람이 읽는 줄이다.
        lines.append("동기화 대조 — 지문은 내용의 해시, 금액 없음")
        lines.append("마지막 저장: \(Autosave.shared.lastSaveAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "이번 실행에서 없음")")
        for row in DataFingerprint.rows(in: context) {
            let latest = row.latest.map { $0.formatted(date: .numeric, time: .standard) } ?? "-"
            lines.append("\(row.entity) \(row.count)건 · \(row.digest) · \(latest)")
        }
        // 화면과 같은 순서다 (`Plan.ordered`, 167번). 1번이 화면이 쓰는 계획이다.
        let plans = Plan.ordered(context.all(Plan.self))
        if let plan = plans.first {
            let groups = DataFingerprint.planGroups(plan)
                .map { "\($0.group) \($0.digest)" }.joined(separator: " · ")
            lines.append("계획 묶음: \(groups)")
            lines.append("계획 시각: 만든 \(plan.createdAt.formatted(date: .numeric, time: .standard)) · 고친 \(plan.updatedAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "-") · id 꼬리 \(plan.id.uuidString.suffix(4))")
        }
        // **계획이 둘 이상이면 전부 적는다** (165번). 두 기기가 만든 시각이 같은
        // 계획을 "첫 번째" 로 골라도 **같은 레코드라는 보장이 없다** — 백업
        // 되돌리기는 시각을 그대로 베끼므로 동점이 생기고, 동점은 기기마다 다르게
        // 풀린다. 레코드 id 꼬리가 같아야 같은 것이다.
        if plans.count > 1 {
            lines.append("계획 \(plans.count)개 — 화면은 1번을 쓴다:")
            for (index, extra) in plans.enumerated() {
                let words = DataFingerprint.planGroups(extra).first?.digest ?? "-"
                lines.append("  \(index + 1). id 꼬리 \(extra.id.uuidString.suffix(4)) · 만든 \(extra.createdAt.formatted(date: .numeric, time: .standard)) · 고친 \(extra.updatedAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "-") · 문서 글귀 \(words)")
            }
        }
        lines.append("")

        // **동기화 실패 이력** (165번). 마지막 한 번이 성공이어도 그 앞의 실패는
        // 남아 있어야 한다 — 실패한 레코드는 다음 성공에 실려 가지 않는다.
        let failures = monitor.recentFailures
        if failures.isEmpty {
            lines.append("동기화 실패: 이번 실행에서 없음 (시도 \(monitor.history.count)건)")
        } else {
            lines.append("동기화 실패 \(failures.count)건 (이번 실행 시도 \(monitor.history.count)건):")
            for failure in failures.prefix(10) {
                lines.append("  \(failure.kind.label) \(failure.endedAt.formatted(date: .numeric, time: .standard)) — \(failure.failure ?? "이유 없음")")
            }
        }
        lines.append("")

        // 알림
        let center = UNUserNotificationCenter.current()
        let auth = await ReviewNotifications.authorizationStatus()
        let pending = await center.pendingNotificationRequests()
        lines.append("알림 권한: \(authLabel(auth)) · 걸려 있는 알림 \(pending.count)개")
        lines.append("주간 점검 알림: \(Calendar.current.weekdaySymbols[max(0, min(6, ReviewSettings.weekday - 1))]) \(String(format: "%02d:%02d", ReviewSettings.hour, ReviewSettings.minute)) · 목실감 \(DiarySettings.enabled ? "켬" : "끔") · 회고 \(UserDefaults.standard.object(forKey: RetrospectiveNotifications.enabledKey) == nil || UserDefaults.standard.bool(forKey: RetrospectiveNotifications.enabledKey) ? "켬" : "끔")")
        return lines.joined(separator: "\n")
    }

    private static func attempt(_ attempt: CloudKitSyncMonitor.Attempt?) -> String {
        guard let attempt else { return "아직 없음" }
        let when = attempt.endedAt.formatted(date: .numeric, time: .shortened)
        let failure = attempt.failure.map { " — \($0)" } ?? ""
        return "\(attempt.succeeded ? "성공" : "실패") \(when)\(failure)"
    }

    private static func accountLabel(_ status: CKAccountStatus?) -> String {
        switch status {
        case .available: return "연결됨"
        case .noAccount: return "로그인 안 됨"
        case .restricted: return "제한됨"
        case .couldNotDetermine: return "확인 불가"
        case .temporarilyUnavailable: return "일시적으로 사용 불가"
        case nil: return "확인 중"
        default: return "알 수 없음"
        }
    }

    private static func authLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "허용"
        case .provisional: return "임시 허용"
        case .ephemeral: return "일시 허용"
        case .denied: return "거부"
        case .notDetermined: return "아직 안 물음"
        @unknown default: return "알 수 없음"
        }
    }
}
