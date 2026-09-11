import CoreData
import Foundation
import UserNotifications

/// 목·실·감 알림 설정. 기본은 **꺼짐** — 켜면 저녁 9시.
enum DiarySettings {
    static let enabledKey = "diary.reminderEnabled"
    static let hourKey = "diary.reminderHour"
    static let minuteKey = "diary.reminderMinute"

    static let defaultHour = 21
    static let defaultMinute = 0

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var hour: Int { value(hourKey, defaultHour) }
    static var minute: Int { value(minuteKey, defaultMinute) }

    private static func value(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil
            ? fallback : UserDefaults.standard.integer(forKey: key)
    }
}

/// **매일 알림** (docs/05-roadmap.md 마지막 묶음 1, 선택).
///
/// 주간 점검 알림과 따로 건다 — 식별자도 카테고리도 다르다. 반복 트리거 하나가
/// 기본인데, 반복 트리거는 "오늘은 이미 적었으니 건너뛰기" 를 못 한다. 그래서
/// 오늘 이미 적었고 아직 시각 전이면 **내일부터 7일치 한 번짜리**로 바꿔 걸고,
/// 다음에 앱이 뜰 때 다시 반복으로 돌린다.
///
/// 예전에는 내일 **하루치만** 걸었다. 그 뒤 앱을 안 열면 반복을 걷어낸 채라
/// 모레부터 알림이 끊겼다 (docs/05-roadmap.md 동결 이슈 1). 7일치면 일주일은
/// 앱을 안 열어도 이어지고, 여는 순간 다시 채워진다.
enum DiaryNotifications {

    enum Identifier {
        static let daily = "diary-daily"
        /// 옛 식별자. 지금은 `once(_:)` 로 날짜별로 건다 — 지울 때만 쓴다.
        static let once = "diary-once"
        static let category = "DIARY"
        /// 오늘 적은 뒤 거는 한 번짜리 알림의 날 수.
        static let onceDays = 7

        static func once(_ dayOffset: Int) -> String { "diary-once-\(dayOffset)" }
        static var allOnce: [String] { [once] + (1...onceDays).map(once(_:)) }
    }

    /// 오늘 일기에 글자가 하나라도 있나.
    @MainActor
    static func todayWritten(_ entries: [DiaryEntry]) -> Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return entries.contains {
            $0.day == today && !($0.goal.isEmpty && $0.result.isEmpty && $0.gratitude.isEmpty)
        }
    }

    /// 여러 번 불러도 안전하다 — 같은 식별자를 덮어쓴다.
    static func refresh(todayWritten: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.daily] + Identifier.allOnce)

        guard DiarySettings.enabled else { return }
        guard await center.notificationSettings().authorizationStatus != .denied else { return }

        let content = UNMutableNotificationContent()
        content.title = "오늘의 목 · 실 · 감"
        content.body = "목표 · 실적 · 감사, 한 줄씩 적어 두세요."
        content.categoryIdentifier = Identifier.category
        content.sound = .default

        let calendar = Calendar.current
        let now = Date.now
        let todayAt = calendar.date(bySettingHour: DiarySettings.hour, minute: DiarySettings.minute,
                                    second: 0, of: now) ?? now

        if todayWritten, now < todayAt {
            // 오늘 몫은 끝났다. 내일부터 7일, 같은 시각에 한 번씩.
            for offset in 1...Identifier.onceDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: todayAt) else { continue }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: day)
                let request = UNNotificationRequest(
                    identifier: Identifier.once(offset), content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try? await center.add(request)
            }
            return
        }

        var components = DateComponents()
        components.hour = DiarySettings.hour
        components.minute = DiarySettings.minute
        let request = UNNotificationRequest(
            identifier: Identifier.daily, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        try? await center.add(request)
    }
}
