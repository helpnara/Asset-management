import Foundation

/// **얼마를 넣어서 얼마가 자랐나** (docs/08-feedback.md 80번, C1).
///
/// 총액 증감만 보면 "이번 주 +300만" 이 시장이 준 것인지 내가 넣은 것인지
/// 모른다. 이 앱은 거래를 입력받지 않으므로(ADR-0005) 적립분을 **계획의 월
/// 적립으로 어림**한다 — 기간의 날수만큼 월 적립을 비례로 깔고, 그 사이의
/// 목돈 이벤트는 날짜대로 더한다. 나머지가 수익이다. 추정임을 화면에 적는다.
public struct ChangeAttribution: Sendable, Hashable {
    /// 기간 동안의 총액 증감 (끝 − 시작).
    public let change: Money
    /// 넣은 것으로 어림한 금액 (월 적립 × 날수/평균 한 달 + 목돈).
    public let contributed: Money
    /// 자란 것 = 증감 − 적립.
    public let gained: Money

    /// 한 달의 평균 날수. 365.25 ÷ 12.
    public static let daysPerMonth = Decimal(string: "30.4375")!

    public static func estimate(
        from start: Money,
        to end: Money,
        monthlyContribution: Money,
        days: Int,
        lumpSums: Money? = nil
    ) -> ChangeAttribution {
        let change = end - start
        let prorated = monthlyContribution.scaled(by: Decimal(max(days, 0)) / daysPerMonth)
        let contributed = prorated + (lumpSums ?? .zero(start.currency))
        return ChangeAttribution(change: change, contributed: contributed, gained: change - contributed)
    }
}
