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

// MARK: - 은퇴 이후

/// 노후 준비 앱인데 은퇴 이후가 비어 있으면 절반만 만든 것이다.
/// 여기 숫자는 전부 파이썬으로 따로 굴려 대조했다.
@Suite("Projection — 은퇴 후 인출")
struct RetirementDrawdownTests {

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

    /// 은퇴 즉시 인출을 시작하는 40년짜리 입력.
    private func drawdown(
        start: Int = 1_000_000_000,
        spending: Int,
        incomes: [IncomeStreamInput] = []
    ) -> ProjectionInput {
        let begin = date("2026-01-01")
        return ProjectionInput(
            startDate: begin,
            endDate: calendar.date(byAdding: .year, value: 40, to: begin)!,
            startingBalance: Money(start, currency: .krw),
            monthlyContribution: .zero(.krw),
            annualReturn: Ratio(basisPoints: 500),
            inflation: Ratio(basisPoints: 200),
            retirementDate: begin,
            monthlyRetirementSpending: Money(spending, currency: .krw),
            incomes: incomes
        )
    }

    private func income(_ amount: Int, from year: Int, linked: Bool = true) -> IncomeStreamInput {
        IncomeStreamInput(label: "연금", monthlyAmount: Money(amount, currency: .krw),
                          startYear: year, endYear: nil, isInflationLinked: linked)
    }

    @Test("생활비를 안 넣으면 인출하지 않는다 — 예전 동작 그대로다")
    func noSpendingNoWithdrawal() {
        let result = Projection.run(drawdown(spending: 0), calendar: calendar)
        #expect(result.depletion == nil)
        #expect(result.last?.nominal == Money(7_039_988_676, currency: .krw))
    }

    @Test("꺼내 쓰면 언젠가 바닥난다")
    func depletes() {
        // 10억에서 월 500만(오늘 돈)을 꺼내면 273개월 뒤 바닥난다.
        // 물가 2%를 태우므로 생활비는 해마다 커진다 — 그래서 22.8년이다.
        let result = Projection.run(drawdown(spending: 5_000_000), calendar: calendar)
        #expect(result.depletion == date("2048-10-01"))
        #expect(result.last?.nominal == .zero(.krw))
    }

    @Test("연금이 있으면 그만큼만 꺼낸다")
    func pensionReducesWithdrawal() {
        // 생활비 500만 − 연금 200만 = 순인출 300만. 40년을 버티고도 10.2억이 남는다.
        let result = Projection.run(
            drawdown(spending: 5_000_000, incomes: [income(2_000_000, from: 2026)]),
            calendar: calendar
        )
        #expect(result.depletion == nil)
        #expect(result.last?.nominal == Money(1_021_954_446, currency: .krw))
    }

    @Test("물가연동이 안 되는 연금은 갈수록 힘이 빠진다")
    func fixedPensionErodes() {
        // 같은 200만이라도 액면가가 고정이면 오늘 돈으로는 계속 줄어든다.
        // 40년이면 버티느냐 바닥나느냐가 갈린다 — 이 차이를 안 보여주면 거짓말이다.
        let linked = Projection.run(
            drawdown(spending: 5_000_000, incomes: [income(2_000_000, from: 2026, linked: true)]),
            calendar: calendar
        )
        let fixed = Projection.run(
            drawdown(spending: 5_000_000, incomes: [income(2_000_000, from: 2026, linked: false)]),
            calendar: calendar
        )
        #expect(linked.depletion == nil)
        #expect(fixed.depletion == date("2065-12-01"))
    }

    @Test("연금이 생활비보다 많아도 자산이 늘지는 않는다")
    func surplusIsNotSaved() {
        // 남는 연금을 자산에 더하면 은퇴 후 저축을 가정하는 셈이다.
        // 여기서 낙관을 더할 이유가 없다 — 인출 0과 결과가 같아야 한다.
        let surplus = Projection.run(
            drawdown(spending: 1_000_000, incomes: [income(3_000_000, from: 2026)]),
            calendar: calendar
        )
        let none = Projection.run(drawdown(spending: 0), calendar: calendar)
        #expect(surplus.last?.nominal == none.last?.nominal)
    }

    @Test("아직 시작 안 한 연금은 세지 않는다")
    func pensionStartYear() {
        // 2040년부터 나오는 연금은 그때까지 아무 도움이 안 된다. 바닥나는 것을
        // 막지는 못하고 8년쯤 늦출 뿐이다 — 처음에 "연금이 있으니 버티겠지" 하고
        // 적었다가 둘 다 0으로 끝나는 것을 파이썬으로 확인하고 고친 자리다.
        let later = Projection.run(
            drawdown(spending: 5_000_000, incomes: [income(2_000_000, from: 2040)]),
            calendar: calendar
        )
        let never = Projection.run(drawdown(spending: 5_000_000), calendar: calendar)

        #expect(never.depletion == date("2048-10-01"))
        #expect(later.depletion == date("2056-02-01"))
        #expect(later.depletion! > never.depletion!)
    }

    @Test("연말 결산은 인출까지 세어야 앞뒤가 맞는다")
    func yearIdentityWithWithdrawal() {
        let result = Projection.run(
            drawdown(spending: 3_000_000, incomes: [income(1_000_000, from: 2026)]),
            calendar: calendar
        )
        var previous = Money(1_000_000_000, currency: .krw)
        for year in result.years {
            // 연말 = 연초 + 적립 + 목돈 + 수익 − 인출. 정의상 항상 맞아야 한다.
            #expect(previous + year.contributed + year.cashEvents + year.gain - year.withdrawn
                    == year.endBalance)
            previous = year.endBalance
        }
        #expect(result.years.contains { !$0.withdrawn.isZero })
    }

    @Test("적립 구간과 인출 구간이 한 궤적에 이어진다")
    func twoPhases() {
        let begin = date("2026-01-01")
        let input = ProjectionInput(
            startDate: begin,
            endDate: calendar.date(byAdding: .year, value: 40, to: begin)!,
            startingBalance: Money(100_000_000, currency: .krw),
            monthlyContribution: Money(2_000_000, currency: .krw),
            annualReturn: Ratio(basisPoints: 500),
            inflation: Ratio(basisPoints: 200),
            retirementDate: calendar.date(byAdding: .year, value: 20, to: begin)!,
            monthlyRetirementSpending: Money(4_000_000, currency: .krw),
            incomes: [income(1_500_000, from: 2046)]
        )
        let result = Projection.run(input, calendar: calendar)

        // 정점은 은퇴 직후가 아니라 한참 뒤(2056)에 온다. 처음에는 수익이
        // 순인출보다 커서 계속 오르다가, 물가가 생활비를 밀어 올리면서 꺾인다.
        // "은퇴하면 바로 줄어든다"는 직관이 틀리는 자리다.
        let peak = result.points.map(\.nominal).max()!
        #expect(result.last?.nominal == Money(1_065_867_606, currency: .krw))
        #expect(result.last!.nominal < peak)
        #expect(result.depletion == nil)
    }
}

// MARK: - 수익률 프로필

/// 순자산을 통째로 한 수익률에 굴리던 것을 덩어리로 나눴다
/// (docs/08-feedback.md 11번).
///
/// **기댓값은 파이썬으로 따로 계산해 대조했다** (CLAUDE.md 규칙).
/// 월마다 은행가 반올림이 들어가서 `1억 × 1.08¹⁰` 같은 손 계산과는 어긋난다.
@Suite("Projection — 수익률 프로필")
struct ReturnProfileTests {

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

    private func bucket(_ profile: ReturnProfile, _ amount: Int, _ bp: Int) -> BalanceBucket {
        BalanceBucket(profile: profile,
                      amount: Money(amount, currency: .krw),
                      annualReturn: Ratio(basisPoints: bp))
    }

    private func input(years: Int, buckets: [BalanceBucket],
                       monthly: Int = 0, returnBP: Int = 800) -> ProjectionInput {
        ProjectionInput(
            startDate: date("2026-01-01"),
            endDate: calendar.date(byAdding: .year, value: years, to: date("2026-01-01"))!,
            buckets: buckets,
            monthlyContribution: Money(monthly, currency: .krw),
            annualReturn: Ratio(basisPoints: returnBP)
        )
    }

    @Test("덩어리마다 자기 속도로 자란다")
    func eachBucketGrowsAtItsOwnRate() {
        let result = Projection.run(
            input(years: 10, buckets: [
                bucket(.investment, 100_000_000, 800),
                bucket(.lowYield, 50_000_000, 200),
                bucket(.fixed, 200_000_000, 0)
            ]),
            calendar: calendar
        )
        // 215,892,496 + 60,949,720 + 200,000,000
        #expect(result.last?.nominal == Money(476_842_216, currency: .krw))
    }

    @Test("전세보증금은 23년이 지나도 그대로다 — 이 항목의 요지다")
    func fixedBucketDoesNotGrow() {
        let result = Projection.run(
            input(years: 23, buckets: [bucket(.fixed, 200_000_000, 0)]),
            calendar: calendar
        )
        #expect(result.last?.nominal == Money(200_000_000, currency: .krw))

        // 예전처럼 전액을 8% 로 굴리면 11.7억이 됐다. 그 차이가 이 변경의 이유다.
        let asInvestment = Projection.run(
            input(years: 23, buckets: [bucket(.investment, 200_000_000, 800)]),
            calendar: calendar
        )
        #expect(asInvestment.last?.nominal == Money(1_174_292_735, currency: .krw))
    }

    @Test("덩어리를 안 나누면 전액이 투자자산이다 — 예전 동작 그대로다")
    func legacyInitIsAllInvestment() {
        let legacy = ProjectionInput(
            startDate: date("2026-01-01"),
            endDate: calendar.date(byAdding: .year, value: 10, to: date("2026-01-01"))!,
            startingBalance: Money(100_000_000, currency: .krw),
            monthlyContribution: .zero(.krw),
            annualReturn: Ratio(basisPoints: 800)
        )
        #expect(legacy.buckets.count == 1)
        #expect(legacy.buckets[0].profile == .investment)
        #expect(legacy.startingBalance == Money(100_000_000, currency: .krw))
        #expect(Projection.run(legacy, calendar: calendar).last?.nominal
                == Money(215_892_496, currency: .krw))
    }

    @Test("투자자산 덩어리가 없어도 적립은 0%로 굴지 않는다")
    func contributionsLandInTheInvestmentBucket() {
        // 전세보증금만 있는 초기 상태. 투자자산 덩어리가 없으면 적립이 고정
        // 덩어리로 들어가 한 푼도 안 불어난다. 그래서 빈 투자자산을 만들어 둔다.
        let onlyFixed = input(years: 1, buckets: [bucket(.fixed, 0, 0)], monthly: 1_000_000)
        #expect(onlyFixed.buckets.contains { $0.profile == .investment })

        let result = Projection.run(onlyFixed, calendar: calendar)
        // 월 100만을 열두 번 넣고 연 8% 로 굴린 값. 원금 1,200만보다 크다.
        #expect(result.last?.nominal == Money(12_513_886, currency: .krw))
    }

    @Test("인출은 투자자산부터 꺼내고, 마르면 다음 덩어리로 넘어간다")
    func drawdownStartsWithInvestment() {
        let start = date("2026-01-01")
        let input = ProjectionInput(
            startDate: start,
            endDate: calendar.date(byAdding: .month, value: 3, to: start)!,
            buckets: [
                BalanceBucket(profile: .investment, amount: Money(10_000_000, currency: .krw),
                              annualReturn: .zero),
                BalanceBucket(profile: .fixed, amount: Money(20_000_000, currency: .krw),
                              annualReturn: .zero)
            ],
            monthlyContribution: .zero(.krw),
            annualReturn: .zero,
            retirementDate: start,                       // 시작하자마자 인출 구간
            monthlyRetirementSpending: Money(5_000_000, currency: .krw)
        )
        let result = Projection.run(input, calendar: calendar)

        // 1개월 투자 500만 남음 · 2개월 투자 0 · 3개월 고정에서 500만 빠져 1,500만
        #expect(result.last?.nominal == Money(15_000_000, currency: .krw))
        // 투자자산이 마른 것이지 전체가 바닥난 것은 아니므로 고갈이 아니다.
        #expect(result.depletion == nil)
    }

    @Test("계좌 종류가 프로필을 정한다")
    func accountKindMapsToProfile() {
        #expect(AccountKind.general.returnProfile == .investment)
        #expect(AccountKind.irp.returnProfile == .investment)
        #expect(AccountKind.deposit.returnProfile == .lowYield)
        #expect(AccountKind.insurance.returnProfile == .lowYield)
        #expect(AccountKind.realEstate.returnProfile == .realEstate)
        #expect(AccountKind.leaseDeposit.returnProfile == .fixed)
        #expect(AccountKind.receivable.returnProfile == .fixed)
        // 받을 돈은 자산이지만 굴러가는 돈이 아니다.
        #expect(AccountKind.receivable.countsAsInvestable == false)
        #expect(AccountKind.receivable.isLiability == false)
    }

    @Test("계좌 종류가 점검 주기 기본값도 정한다")
    func accountKindMapsToCadence() {
        #expect(AccountKind.general.defaultCadence == .weekly)
        #expect(AccountKind.insurance.defaultCadence == .monthly)
        #expect(AccountKind.leaseDeposit.defaultCadence == .fixed)
        #expect(AccountKind.receivable.defaultCadence == .fixed)
    }
}
