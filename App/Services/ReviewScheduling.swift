import Core
import Foundation
import SwiftUI

enum ReviewSettings {
    static let weekdayKey = "review.weekday"
    static let hourKey = "review.hour"
    static let minuteKey = "review.minute"
    static let followUpKey = "review.followUp"

    /// 7 = 토요일
    static let defaultWeekday = 7
    static let defaultHour = 9
    static let defaultMinute = 0

    static var weekday: Int { value(weekdayKey, defaultWeekday) }
    static var hour: Int { value(hourKey, defaultHour) }
    static var minute: Int { value(minuteKey, defaultMinute) }
    static var followUpEnabled: Bool {
        UserDefaults.standard.object(forKey: followUpKey) as? Bool ?? true
    }

    private static func value(_ key: String, _ fallback: Int) -> Int {
        let stored = UserDefaults.standard.integer(forKey: key)
        return UserDefaults.standard.object(forKey: key) == nil ? fallback : stored
    }
}

/// 알림 등록을 한곳에서 한다. 앱이 뜰 때마다 부르며 여러 번 불러도 안전하다.
enum ReviewScheduling {

    static func refresh(holdings: [Holding], sessions: [ReviewSession]) async {
        guard await ReviewNotifications.authorizationStatus() != .denied else { return }

        let itemCount = holdings.filter { $0.cadence != .fixed }.count
        let completed = sessions.filter(\.isComplete).map(\.weekAnchor)
        let streak = ReviewWeek.streak(completedAnchors: completed, asOf: .now)

        await ReviewNotifications.scheduleWeekly(
            weekday: ReviewSettings.weekday,
            hour: ReviewSettings.hour,
            minute: ReviewSettings.minute,
            itemCount: itemCount,
            streak: streak
        )

        let thisWeek = ReviewWeek.anchor(for: .now)
        let didThisWeek = completed.contains(thisWeek)

        if didThisWeek || !ReviewSettings.followUpEnabled {
            ReviewNotifications.cancelFollowUp()
            return
        }

        // 이번 주 점검일 다음날 같은 시각. 이미 지났으면 걸지 않는다.
        let calendar = Calendar.current
        guard
            let reviewDay = calendar.date(bySetting: .weekday, value: ReviewSettings.weekday, of: thisWeek)
                ?? calendar.date(byAdding: .day, value: 0, to: thisWeek),
            let followUp = calendar.date(
                bySettingHour: ReviewSettings.hour,
                minute: ReviewSettings.minute,
                second: 0,
                of: calendar.date(byAdding: .day, value: 1, to: reviewDay) ?? reviewDay
            ),
            followUp > .now
        else {
            ReviewNotifications.cancelFollowUp()
            return
        }

        await ReviewNotifications.scheduleFollowUp(at: followUp)
    }
}
