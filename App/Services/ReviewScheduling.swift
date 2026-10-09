import Core
import Foundation
import SwiftUI

enum ReviewSettings {
    static let weekdayKey = "review.weekday"
    static let hourKey = "review.hour"
    static let minuteKey = "review.minute"
    static let followUpKey = "review.followUp"
    /// 주간 알림에 지난주 총액을 함께 보여줄 것인가.
    /// 알림은 잠긴 화면에도 뜬다 — 기본은 표시하지 않음이다.
    static let notificationAmountKey = "review.showsAmount"

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
    static var showsAmountInNotification: Bool {
        UserDefaults.standard.bool(forKey: notificationAmountKey)
    }

    // MARK: - 사람에게 말하는 점검일 (194번 U4)
    //
    // 알림 요일을 일요일 20시로 바꿔도 화면 곳곳이 "토요일" 이었다 — 스토어 설명은 "정한
    // 요일과 시각에" 라고 약속한다. 기록의 주(토요일 기준, `ReviewWeek`)는 그대로 두고,
    // 사람에게 말하는 날짜만 여기서 짓는다.

    /// `토요일`
    static var weekdayName: String {
        let names = ["일", "월", "화", "수", "목", "금", "토"]
        return names[((weekday - 1) % 7 + 7) % 7] + "요일"
    }

    /// `오전 9시` · `오후 8시 30분`
    static var timeText: String {
        let half = hour < 12 ? "오전" : "오후"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(half) \(h12)시" : "\(half) \(h12)시 \(minute)분"
    }

    /// 오늘부터 정한 요일까지 남은 날. 오늘이면 0.
    static func daysUntilReviewDay(from date: Date = .now, calendar: Calendar = .app) -> Int {
        let today = calendar.component(.weekday, from: date)
        return ((weekday - today) % 7 + 7) % 7
    }

    /// 이번 점검일 — 오늘이 그 요일이면 오늘.
    static func upcomingReviewDay(from date: Date = .now, calendar: Calendar = .app) -> Date {
        calendar.date(byAdding: .day, value: daysUntilReviewDay(from: date, calendar: calendar),
                      to: calendar.startOfDay(for: date)) ?? date
    }

    /// 다음 점검일 — 오늘 끝냈으면 다음 주 그 요일.
    static func nextReviewDay(after date: Date = .now, calendar: Calendar = .app) -> Date {
        let days = daysUntilReviewDay(from: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: days == 0 ? 7 : days,
                             to: calendar.startOfDay(for: date)) ?? date
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
        /// 지난 점검의 총액. 알림에 금액을 보여주기로 했을 때만 쓴다.
        var lastTotalMinor: Int

        @MainActor
        init(holdings: [Holding], sessions: [ReviewSession]) {
            self.itemCount = holdings.filter { $0.isDue() }.count
            let completed = sessions.filter(\.isComplete)
            self.completedAnchors = completed.map(\.weekAnchor)
            self.lastTotalMinor = completed
                .max { $0.weekAnchor < $1.weekAnchor }?
                .totalValueMinor ?? 0
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
            streak: streak,
            lastTotalMinor: ReviewSettings.showsAmountInNotification ? input.lastTotalMinor : 0
        )

        let thisWeek = ReviewWeek.anchor(for: .now)
        let didThisWeek = completed.contains(thisWeek)

        if didThisWeek || !ReviewSettings.followUpEnabled {
            ReviewNotifications.cancelFollowUp()
            return
        }

        // 이번 주 점검일 다음날 같은 시각. 이미 지났으면 걸지 않는다.
        let calendar = Calendar.app
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
