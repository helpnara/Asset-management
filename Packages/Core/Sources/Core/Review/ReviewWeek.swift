import Foundation

/// 주간 점검의 주차 계산.
///
/// 점검일은 토요일이지만 하루 이틀 밀려서 할 수도 있으므로
/// **토요일 00:00 ~ 다음 금요일 23:59** 를 한 점검 주기로 본다.
/// 일요일에 적어도 그 주 토요일 기록으로 남는다.
public enum ReviewWeek {

    /// 그 날짜가 속한 점검 주의 토요일.
    public static func anchor(for date: Date, calendar: Calendar = .app) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        // Foundation weekday: 1 = 일요일 … 7 = 토요일
        let daysSinceSaturday = calendar.component(.weekday, from: startOfDay) % 7
        return calendar.date(byAdding: .day, value: -daysSinceSaturday, to: startOfDay) ?? startOfDay
    }

    /// **같은 점검 주인가 — 기기 시간대가 달라도** (docs/08-feedback.md 194번 D3).
    ///
    /// 기준일은 **그 기기 시간대의** 토요일 자정이다. 아빠가 유럽 출장 중에 점검하면
    /// 기준일이 한국 가족의 것과 몇 시간 어긋나서, 시각이 정확히 같은지(`==`)로 찾던
    /// 자리들이 같은 주를 둘로 갈랐다 — 세션 · 스냅샷이 하나씩 더 생기고 정리도
    /// 못 잡았다. 저장된 기준일은 그대로 두고 **비교만** 이것으로 한다.
    ///
    /// 기준일에 12시간을 더한 UTC 날짜로 견준다. UTC−10 ~ UTC+12 에서 같은
    /// 토요일 자정은 모두 같은 날이 되고, 이웃 토요일과는 7일 떨어진다.
    public static func isSameWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        dayKey(lhs) == dayKey(rhs)
    }

    /// 기준일의 날 번호(1970-01-01 부터). 같은 토요일이면 시간대가 달라도 같다.
    public static func dayKey(_ anchor: Date) -> Int {
        Int(((anchor.timeIntervalSince1970 + 43_200) / 86_400).rounded(.down))
    }

    /// 기준일 근처(앞뒤 하루)를 고르는 조건 — 저장소에서 같은 주 후보를 꺼낼 때.
    /// 꺼낸 뒤 `isSameWeek` 로 다시 거른다.
    public static func nearbyRange(of anchor: Date) -> (lower: Date, upper: Date) {
        (anchor.addingTimeInterval(-86_400), anchor.addingTimeInterval(86_400))
    }

    /// 다음 점검일(토요일).
    public static func nextSaturday(after date: Date, calendar: Calendar = .app) -> Date {
        let current = anchor(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 7, to: current) ?? current
    }

    /// 점검일까지 남은 일수. 오늘이 토요일이면 0.
    public static func daysUntilReview(from date: Date, calendar: Calendar = .app) -> Int {
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
        calendar: Calendar = .app
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
