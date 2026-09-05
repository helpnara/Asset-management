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

    @Test("목돈이 들어오면 남은 기간만큼 함께 굴러간다")
    func cashEvent() {
        var withEvent = input(years: 10, start: 100_000_000, monthly: 1_000_000, returnBP: 800)
        withEvent.cashEvents = [
            CashEventInput(date: date("2027-01-01"), amount: Money(100_000_000, currency: .krw),
                           label: "전세보증금 전환")
        ]
        let result = Projection.run(withEvent, calendar: calendar)
        let plain = Projection.run(input(years: 10, start: 100_000_000, monthly: 1_000_000, returnBP: 800),
                                   calendar: calendar)

        #expect(result.last?.nominal == Money(598_362_328, currency: .krw))
        // 1억이 9년 굴러 2억이 된다. 목돈을 빼놓고 그린 궤적은 궤적이 아니다.
        #expect((result.last!.nominal - plain.last!.nominal) == Money(201_186_627, currency: .krw))
    }

    @Test("기간 밖의 목돈은 무시한다")
    func cashEventOutOfRange() {
        var late = input(years: 5, start: 100_000_000, monthly: 0, returnBP: 800)
        late.cashEvents = [
            CashEventInput(date: date("2040-01-01"), amount: Money(500_000_000, currency: .krw))
        ]
        let plain = Projection.run(input(years: 5, start: 100_000_000, monthly: 0, returnBP: 800),
                                   calendar: calendar)
        #expect(Projection.run(late, calendar: calendar).last?.nominal == plain.last?.nominal)
    }

    @Test("연도별 결산이 앞뒤로 이어진다")
    func yearSummaries() {
        let result = Projection.run(input(years: 5, start: 100_000_000, monthly: 1_000_000, returnBP: 800),
                                    calendar: calendar)
        #expect(!result.years.isEmpty)

        // 연말 잔고 = 연초 + 적립 + 목돈 + 수익. 정의상 항상 맞아야 한다.
        var previous = Money(100_000_000, currency: .krw)
        for year in result.years {
            #expect(previous + year.contributed + year.cashEvents + year.gain == year.endBalance)
            previous = year.endBalance
        }
        #expect(result.years.last?.endBalance == result.last?.nominal)
    }

    @Test("수익이 적립금을 넘어서는 해를 찾는다")
    func returnsExceedContribution() {
        let result = Projection.run(input(years: 20, start: 100_000_000, monthly: 1_000_000, returnBP: 800),
                                    calendar: calendar)
        let crossing = result.milestone(.returnsExceedContribution)
        #expect(crossing != nil)
        // 2026-01 시작이면 2029년에 복리가 내 손을 앞지른다.
        // 첫 해(2026)는 11개월짜리 부분 연도라 판정에서 빼기 때문에,
        // 12개월 블록으로 세는 "4년차"와는 한 해 어긋난다. 달력 연도가 기준이다.
        #expect(crossing?.year == 2029)
    }

    @Test("목표를 넘기지 못하면 마일스톤도 없다")
    func targetNotReached() {
        var modest = input(years: 5, start: 10_000_000, monthly: 200_000, returnBP: 500)
        modest.targetAmount = Money(10_000_000_000, currency: .krw)
        let result = Projection.run(modest, calendar: calendar)

        #expect(result.last?.nominal == Money(26_380_819, currency: .krw))
        #expect(result.milestone(.targetReached) == nil)   // 100억은 못 넘긴다
        #expect(result.milestone(.doubled)?.year == 2029)  // 두 배는 넘긴다
    }

    @Test("아슬아슬하게 못 넘기면 마일스톤도 없다")
    func doubledNotReached() {
        // 월 10만이면 5년 뒤 19,571,813원. 두 배(2,000만)에 42만원 모자란다.
        // 처음에 "당연히 두 배 되겠지" 하고 적었다가 틀렸던 자리다.
        let tight = input(years: 5, start: 10_000_000, monthly: 100_000, returnBP: 500)
        let result = Projection.run(tight, calendar: calendar)
        #expect(result.last?.nominal == Money(19_571_813, currency: .krw))
        #expect(result.milestone(.doubled) == nil)
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
