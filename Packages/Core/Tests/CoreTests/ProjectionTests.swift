import Foundation
import Testing
@testable import Core

@Suite("Projection — 결정론적 궤적")
struct ProjectionTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    private func input(
        years: Int,
        start: Int,
        monthly: Int,
        returnBP: Int,
        growthBP: Int = 0,
        inflationBP: Int = 0
    ) -> ProjectionInput {
        ProjectionInput(
            startDate: date("2026-01-01"),
            endDate: calendar.date(byAdding: .year, value: years, to: date("2026-01-01"))!,
            startingBalance: Money(start, currency: .krw),
            monthlyContribution: Money(monthly, currency: .krw),
            annualReturn: Ratio(basisPoints: returnBP),
            annualContributionGrowth: Ratio(basisPoints: growthBP),
            inflation: Ratio(basisPoints: inflationBP)
        )
    }

    @Test("수익률이 0이면 적립한 만큼만 쌓인다")
    func noReturn() {
        let result = Projection.run(input(years: 2, start: 0, monthly: 1_000_000, returnBP: 0),
                                    calendar: calendar)
        #expect(result.points.count == 25)          // 시작점 + 24개월
        #expect(result.last?.nominal == Money(24_000_000, currency: .krw))
    }

    @Test("월 복리를 열두 번 곱해도 연 수익률과 1원 차이가 난다")
    func monthlyCompounding() {
        let result = Projection.run(input(years: 1, start: 100_000_000, monthly: 0, returnBP: 800),
                                    calendar: calendar)
        // 108,000,000 이 아니다. 12제곱근을 열두 번 곱하면 정확히 1.08 이 되지 않고,
        // 매달 은행가 반올림을 거치면서 1원이 빈다. 이 1원이 우리가 통제하는 오차의 크기다.
        #expect(result.last?.nominal == Money(107_999_999, currency: .krw))
    }

    @Test("적립과 복리가 함께 굴러간다")
    func contributionAndGrowth() {
        let result = Projection.run(input(years: 10, start: 100_000_000, monthly: 1_000_000, returnBP: 800),
                                    calendar: calendar)
        #expect(result.last?.nominal == Money(397_175_701, currency: .krw))
    }

    @Test("적립액이 해마다 오르면 결과가 커진다")
    func contributionGrowth() {
        let flat = Projection.run(input(years: 10, start: 100_000_000, monthly: 1_000_000, returnBP: 800),
                                  calendar: calendar)
        let rising = Projection.run(input(years: 10, start: 100_000_000, monthly: 1_000_000,
                                          returnBP: 800, growthBP: 300),
                                    calendar: calendar)
        #expect(rising.last?.nominal == Money(419_871_001, currency: .krw))
        #expect(rising.last!.nominal > flat.last!.nominal)
    }

    @Test("실질가치는 명목보다 작다 — 30년 뒤 59억이 지금 얼마인가")
    func realValue() {
        let result = Projection.run(input(years: 10, start: 100_000_000, monthly: 1_000_000,
                                          returnBP: 800, inflationBP: 200),
                                    calendar: calendar)
        #expect(result.last?.nominal == Money(397_175_701, currency: .krw))
        #expect(result.last?.real == Money(325_822_411, currency: .krw))
    }

    @Test("인플레이션이 0이면 명목과 실질이 같다")
    func noInflation() {
        let result = Projection.run(input(years: 5, start: 50_000_000, monthly: 500_000, returnBP: 500),
                                    calendar: calendar)
        #expect(result.last?.nominal == result.last?.real)
    }

    @Test("기간이 없으면 시작점 하나만 돌려준다")
    func degenerate() {
        var single = input(years: 0, start: 30_000_000, monthly: 1_000_000, returnBP: 800)
        single.endDate = single.startDate
        let result = Projection.run(single, calendar: calendar)
        #expect(result.points.count == 1)
        #expect(result.last?.nominal == Money(30_000_000, currency: .krw))
    }

    @Test("연도로 지점을 찾을 수 있다 — 로드맵 타임라인이 쓴다")
    func pointInYear() {
        let result = Projection.run(input(years: 5, start: 100_000_000, monthly: 0, returnBP: 800),
                                    calendar: calendar)
        let year2029 = result.point(inYear: 2029, calendar: calendar)
        #expect(year2029 != nil)
        #expect(result.point(inYear: 2099, calendar: calendar) == nil)
    }
}
