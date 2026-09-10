import Foundation
import UserNotifications

/// **매달 1일 아침, 지난달 회고를 열어 보라고 부른다** (docs/08-feedback.md 86번).
///
/// 주간 점검 알림과 따로 건다. 기본은 켜짐 — 주간 알림을 허용한 사람에게만
/// 간다(권한이 없으면 아무것도 안 건다). 더보기 → 주간 점검 알림에서 끈다.
enum RetrospectiveNotifications {
    static let enabledKey = "retro.monthlyReminder"
    static let identifier = "retro-monthly"
    static let category = "RETRO"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil
            ? true : UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 여러 번 불러도 안전하다 — 같은 식별자를 덮어쓴다.
    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }
        guard await center.notificationSettings().authorizationStatus != .denied else { return }

        let content = UNMutableNotificationContent()
        content.title = "지난달 회고가 준비됐습니다"
        content.body = "얼마를 넣어서 얼마가 자랐는지, 몇 주를 적었는지 한 장으로 보세요."
        content.categoryIdentifier = category
        content.sound = .default

        var components = DateComponents()
        components.day = 1
        components.hour = 9
        components.minute = 0
        let request = UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        try? await center.add(request)
    }
}
