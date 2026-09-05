import Foundation

/// 주간 점검의 주차 계산.
///
/// 점검일은 토요일이지만 하루 이틀 밀려서 할 수도 있으므로
/// **토요일 00:00 ~ 다음 금요일 23:59** 를 한 점검 주기로 본다.
/// 일요일에 적어도 그 주 토요일 기록으로 남는다.
public enum ReviewWeek {

    /// 그 날짜가 속한 점검 주의 토요일.
    public static func anchor(for date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        // Foundation weekday: 1 = 일요일 … 7 = 토요일
        let daysSinceSaturday = calendar.component(.weekday, from: startOfDay) % 7
        return calendar.date(byAdding: .day, value: -daysSinceSaturday, to: startOfDay) ?? startOfDay
    }

    /// 다음 점검일(토요일).
    public static func nextSaturday(after date: Date, calendar: Calendar = .current) -> Date {
        let current = anchor(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 7, to: current) ?? current
    }

    /// 점검일까지 남은 일수. 오늘이 토요일이면 0.
    public static func daysUntilReview(from date: Date, calendar: Calendar = .current) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        return (7 - weekday) % 7
    }

    /// 연속 기록 주차.
    ///
    /// 이번 주를 아직 안 했다고 0으로 만들지 않는다. 토요일이 오기도 전에
    /// "12주 연속"이 0으로 바뀌면 그것만으로 앱을 지운다 — 지난 주까지 이어져 있으면
    /// 그 기록을 그대로 보여준다.
    public static func streak(
        completedAnchors: [Date],
        asOf: Date,
        calendar: Calendar = .current
    ) -> Int {
        let completed = Set(completedAnchors.map { anchor(for: $0, calendar: calendar) })
        guard !completed.isEmpty else { return 0 }

        let thisWeek = anchor(for: asOf, calendar: calendar)
        var cursor = completed.contains(thisWeek)
            ? thisWeek
            : (calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek)

        var count = 0
        while completed.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
