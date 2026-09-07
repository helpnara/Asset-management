import Foundation

/// 1페이지에 이번 주 실을 운용 원칙 고르기 (docs/08-feedback.md 24번).
///
/// 원칙은 강의·세미나를 들을 때마다 늘어나는데 1페이지는 A4 한 장으로 고정이다.
/// 그래서 **몇 개만 골라 싣되, 고르는 방법이 문제**가 된다.
///
/// **난수를 쓰지 않는다.** 1페이지는 문서다. 뽑을 때마다 내용이 달라지면
/// 아내에게 건넨 종이와 다음 주 종이가 다르고, 같은 자산인데 PDF 가 매번 달라져
/// 어느 것이 최신인지 알 수 없고, CI 스크린샷도 매번 달라져 회귀를 볼 수 없다.
///
/// 대신 **주 단위로 돌린다** — 같은 주에는 늘 같은 다섯 개, 주가 바뀌면 다음
/// 다섯 개. 다양성은 그대로면서 이번 주 문서는 늘 같다. 앞의 N개만 고정으로
/// 싣는 것보다 나은 점은 **뒤에 적은 원칙도 언젠가 종이에 오른다**는 것이다.
///
/// 순수 함수라 `Core` 에서 테스트된다. 난수였다면 이 자리에 시드를 넘기는
/// 배관이 생겼을 것이다.
public enum PrincipleRotation {

    /// 주차를 세는 기준점 — **1970-01-01 이 속한 점검 주의 토요일**(1969-12-27).
    ///
    /// 고정된 순간(`timeIntervalSince1970`)이 아니라 기준점도 `anchor` 를 거치게
    /// 한다. 그러지 않으면 표준시가 다른 곳에서 기준점만 하루 중간에 놓여
    /// 두 날짜의 간격이 7의 배수로 떨어지지 않는다.
    private static func epochAnchor(_ calendar: Calendar) -> Date {
        ReviewWeek.anchor(for: Date(timeIntervalSince1970: 0), calendar: calendar)
    }

    /// 이 날짜가 속한 점검 주가 기준점에서 몇 번째 주인가.
    ///
    /// 기준점 이전이면 음수다 — 나머지 연산 쪽에서 접는다.
    public static func weekIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let anchor = ReviewWeek.anchor(for: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: epochAnchor(calendar), to: anchor).day ?? 0
        // 정수 나눗셈은 0 쪽으로 자른다. 음수에서 -1 주와 0 주가 섞이지 않게
        // 내림으로 맞춘다.
        return Int((Double(days) / 7).rounded(.down))
    }

    /// 이번 주에 실을 것들의 **자리 번호**. 0부터 세고, 넘치면 앞으로 돌아온다.
    ///
    /// `take` 개를 연달아 집는다. 개수가 `take` 이하면 전부 싣는다 —
    /// 열 개도 안 되는데 돌려 가며 감출 이유가 없다.
    ///
    /// 한 바퀴 도는 데 걸리는 주는 `count / gcd(count, take)` 다.
    /// 16개에서 5개씩이면 16주, 30개에서 5개씩이면 6주.
    public static func indices(count: Int, take: Int, on date: Date,
                               calendar: Calendar = .current) -> [Int] {
        guard count > 0, take > 0 else { return [] }
        guard count > take else { return Array(0..<count) }

        // 음수 주차도 0 이상으로 접는다. 나머지 연산이 음수를 내면 자리 번호가
        // 배열 밖으로 나간다.
        let week = weekIndex(for: date, calendar: calendar)
        let start = ((week * take) % count + count) % count
        return (0..<take).map { (start + $0) % count }
    }
}
