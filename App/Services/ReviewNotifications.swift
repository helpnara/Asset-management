import Core
import Foundation
import UserNotifications

/// 주간 점검 알림.
///
/// 외부 데이터를 가져오지 않으므로 **알림이 이 앱의 유일한 외부 트리거**다.
/// 알림이 도달하지 않으면 앱이 죽는다. 그만큼 방어적으로 다룬다 (설계 4.5).
enum ReviewNotifications {

    enum Identifier {
        static let weekly = "weekly-review"
        static let followUp = "weekly-review-follow-up"
        static let category = "WEEKLY_REVIEW"
    }

    enum Action {
        static let quickTotal = "QUICK_TOTAL"
        static let openReview = "OPEN_REVIEW"
        static let snooze = "SNOOZE"
    }

    /// 알림에 붙는 동작들. 길게 눌러 펼치면 총액만 먼저 적고 넘어갈 수 있다.
    static func registerCategories() {
        let quickTotal = UNTextInputNotificationAction(
            identifier: Action.quickTotal,
            title: "총액만 기록",
            options: [],
            textInputButtonTitle: "기록",
            textInputPlaceholder: "가족 총자산 (원)"
        )
        let open = UNNotificationAction(
            identifier: Action.openReview,
            title: "전체 입력",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: "다음 주에",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [quickTotal, open, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 매주 같은 요일·시각에 반복. 앱이 뜰 때마다 다시 등록해도 안전하다
    /// (같은 식별자를 덮어쓴다) — 시간대 변경이나 기기 이전에 대비한 것이다.
    static func scheduleWeekly(
        weekday: Int, hour: Int, minute: Int,
        itemCount: Int, streak: Int,
        lastTotalMinor: Int = 0
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "이번 주 점검 — \(itemCount)건"
        var body = streak > 0
            ? "지난주 대비 얼마나 늘었는지 지금 기록하세요. \(streak)주 연속 기록 중"
            : "지난주 대비 얼마나 늘었는지 지금 기록하세요."
        // 알림은 잠긴 화면에도 뜬다. 0이면 설정이 꺼져 있거나 기록이 없는 것이므로
        // 어느 쪽이든 금액을 쓰지 않는다.
        if lastTotalMinor > 0 {
            let amount = KoreanAmountFormatter.abbreviated(
                Money(minorUnits: lastTotalMinor, currency: .krw), suffix: "원")
            body += " (지난주 \(amount))"
        }
        content.body = body
        content.categoryIdentifier = Identifier.category
        content.sound = .default

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: Identifier.weekly,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 점검일에 안 적었으면 다음날 같은 시각에 한 번만 더 부른다.
    /// 두 번째도 놓치면 그 주는 조용히 넘어간다 — 잔소리하는 앱은 지워진다.
    static func scheduleFollowUp(at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "이번 주 점검이 아직입니다"
        content.body = "총액 하나만 적어도 이번 주 기록이 남습니다."
        content.categoryIdentifier = Identifier.category
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: Identifier.followUp,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelFollowUp() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Identifier.followUp])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
