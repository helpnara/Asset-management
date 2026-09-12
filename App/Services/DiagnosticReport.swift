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
        lines.append("느린 부자의 기록 \(MoreView.versionText)")
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
