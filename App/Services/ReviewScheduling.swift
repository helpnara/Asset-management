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

    /// 액터 경계를 건너는 입력.
    ///
    /// SwiftData `@Model` 은 참조 타입이라 `Sendable` 이 아니다. 모델 배열을 그대로
    /// async 함수에 넘기면 Swift 6 가 데이터 경합으로 막는다. 화면 쪽에서 필요한
    /// 값만 뽑아 이 구조체로 건넨다.
    struct Input: Sendable {
        var itemCount: Int
        var completedAnchors: [Date]

        @MainActor
        init(holdings: [Holding], sessions: [ReviewSession]) {
            self.itemCount = holdings.filter { $0.cadence != .fixed }.count
            self.completedAnchors = sessions.filter(\.isComplete).map(\.weekAnchor)
        }
    }

    static func refresh(_ input: Input) async {
        guard await ReviewNotifications.authorizationStatus() != .denied else { return }

        let itemCount = input.itemCount
        let completed = input.completedAnchors
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
