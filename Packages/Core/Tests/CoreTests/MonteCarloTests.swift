import Foundation
import Testing
@testable import Core

/// 몬테카를로는 난수를 쓴다. 그래서 "정답 숫자"를 적을 수 없다 —
/// 적었다면 그건 지어낸 값이다. 대신 분포가 반드시 만족해야 하는
/// 구조적 성질만 못 박는다. 정확한 숫자는 `ProjectionTests` 가 지킨다.
@Suite("MonteCarlo — 변동성 밴드")
struct MonteCarloTests {

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

    private func base(
        years: Int = 10,
        start: Int = 100_000_000,
        monthly: Int = 1_000_000,
        returnBP: Int = 800,
        target: Int? = nil
    ) -> ProjectionInput {
        ProjectionInput(
            startDate: date("2026-01-01"),
            endDate: calendar.date(byAdding: .year, value: years, to: date("2026-01-01"))!,
            startingBalance: Money(start, currency: .krw),
            monthlyContribution: Money(monthly, currency: .krw),
            annualReturn: Ratio(basisPoints: returnBP),
            targetAmount: target.map { Money($0, currency: .krw) }
        )
    }

    private func run(
        _ input: ProjectionInput,
        volatilityBP: Int,
        paths: Int = 400,
        seed: UInt64 = 20_260_905
    ) -> MonteCarloResult {
        MonteCarlo.run(
            MonteCarloInput(base: input,
                            annualVolatility: Ratio(basisPoints: volatilityBP),
                            paths: paths,
                            seed: seed),
            calendar: calendar
        )
    }

    @Test("같은 시드면 같은 그림이 나온다")
    func deterministicSeed() {
        // 사용자가 아무것도 안 바꿨는데 밴드가 흔들리면 그건 결함으로 읽힌다.
        let first = run(base(), volatilityBP: 1_500)
        let second = run(base(), volatilityBP: 1_500)
        #expect(first == second)
    }

    @Test("시드를 바꾸면 그림도 달라진다")
    func differentSeed() {
        let first = run(base(), volatilityBP: 1_500, seed: 1)
        let second = run(base(), volatilityBP: 1_500, seed: 2)
        #expect(first != second)
    }

    @Test("밴드는 항상 p10 ≤ p50 ≤ p90 이다")
    func bandOrdering() {
        let result = run(base(years: 20), volatilityBP: 1_800)
        #expect(!result.bands.isEmpty)
        for band in result.bands {
            #expect(band.p10 <= band.p50)
            #expect(band.p50 <= band.p90)
        }
    }

    @Test("변동성이 0이면 결정론적 궤적과 사실상 같다")
    func zeroVolatilityMatchesProjection() {
        let input = base()
        let deterministic = Projection.run(input, calendar: calendar).last!.nominal
        let result = run(input, volatilityBP: 0, paths: 10)

        // 모든 경로가 같은 길을 걷는다 → 밴드가 한 줄로 붙는다.
        let final = result.bands.last!
        #expect(final.p10 == final.p50)
        #expect(final.p50 == final.p90)

        // Projection 은 매달 은행가 반올림을 하고 몬테카를로는 Double 로 굴린다.
        // 그래서 원 단위로 딱 맞지는 않는다. 3억 9,700만에 몇 원 어긋나는 정도 —
        // 여기서 정확한 숫자를 적으면 그건 지어낸 값이 된다. 상대오차만 못 박는다.
        // 0.01% 를 넘어가면 둘 중 하나가 어긋난 것이다.
        let gap = abs(final.p50.minorUnits - deterministic.minorUnits)
        #expect(gap < deterministic.minorUnits / 10_000)
    }

    @Test("흔들려도 중앙값은 결정론 궤적 근처다 — 기대수익률은 중앙값이다")
    func medianTracksProjection() {
        // 로그정규로 굴리면 중앙값 경로가 예상선 그대로다 (68번). 표본 400 개의
        // 중앙값이라 오차가 있다 — 10년·변동성 15% 면 표본 중앙값의 표준오차가
        // 3% 안팎이므로 10% 안이면 맞다고 본다. 예전 산술 평균 모형은 여기서
        // 연 1.1%p 씩 10년 처져 12% 아래로 떨어졌다.
        let input = base()
        let deterministic = Double(Projection.run(input, calendar: calendar).last!.nominal.minorUnits)
        let p50 = Double(run(input, volatilityBP: 1_500).bands.last!.p50.minorUnits)
        #expect(abs(p50 - deterministic) / deterministic < 0.10)
    }

    @Test("변동성이 커지면 밴드도 넓어진다")
    func widerVolatilityWidensBand() {
        let calm = run(base(years: 20), volatilityBP: 500)
        let rough = run(base(years: 20), volatilityBP: 2_500)

        let calmWidth = calm.bands.last!.p90.minorUnits - calm.bands.last!.p10.minorUnits
        let roughWidth = rough.bands.last!.p90.minorUnits - rough.bands.last!.p10.minorUnits
        #expect(roughWidth > calmWidth)
    }

    @Test("목표가 없으면 성공 확률도 없다")
    func noTargetNoProbability() {
        #expect(run(base(), volatilityBP: 1_500).successProbability == nil)
    }

    @Test("성공 확률은 0과 1 사이다")
    func probabilityBounds() throws {
        let result = run(base(target: 400_000_000), volatilityBP: 1_500)
        let probability = try #require(result.successProbability)
        #expect(probability >= 0)
        #expect(probability <= 1)
    }

    @Test("닿을 수 없는 목표는 0, 이미 넘긴 목표는 1")
    func probabilityExtremes() {
        #expect(run(base(target: 100_000_000_000), volatilityBP: 1_500).successProbability == 0)
        #expect(run(base(target: 1_000), volatilityBP: 1_500).successProbability == 1)
    }

    @Test("목표 도달 확률은 은퇴 시점에서 잰다 — 인출 구간을 붙여도 같다")
    func successIsMeasuredAtRetirement() throws {
        // **실제로 났던 일이다** (docs/08-feedback.md 68번). 지평선 끝에서 재니
        // 30년 인출 뒤 잔고를 목표와 비교해 75% 가 24% 로 떨어졌다.
        let retire = calendar.date(byAdding: .year, value: 10, to: date("2026-01-01"))!
        let accumulateOnly = base(years: 10, target: 300_000_000)
        var withDrawdown = ProjectionInput(
            startDate: date("2026-01-01"),
            endDate: calendar.date(byAdding: .year, value: 40, to: date("2026-01-01"))!,
            startingBalance: Money(100_000_000, currency: .krw),
            monthlyContribution: Money(1_000_000, currency: .krw),
            annualReturn: Ratio(basisPoints: 800),
            targetAmount: Money(300_000_000, currency: .krw),
            retirementDate: retire,
            monthlyRetirementSpending: Money(3_000_000, currency: .krw)
        )
        withDrawdown.postRetirementReturn = Ratio(basisPoints: 500)

        // 경로마다 시드가 따로라 은퇴 달까지 같은 난수를 뽑는다 — 확률이 정확히 같다.
        let a = try #require(run(accumulateOnly, volatilityBP: 1_500).successProbability)
        let b = try #require(run(withDrawdown, volatilityBP: 1_500).successProbability)
        #expect(a == b)

        // 안 바닥날 확률은 인출 구간이 있을 때만 있고, 0 과 1 사이다.
        #expect(run(accumulateOnly, volatilityBP: 1_500).survivalProbability == nil)
        let survival = try #require(run(withDrawdown, volatilityBP: 1_500).survivalProbability)
        #expect((0...1).contains(survival))

        // 생활비가 터무니없으면 전부 바닥난다.
        var ruinous = withDrawdown
        ruinous.monthlyRetirementSpending = Money(100_000_000, currency: .krw)
        #expect(run(ruinous, volatilityBP: 1_500).survivalProbability == 0)
    }

    @Test("목표를 낮출수록 성공 확률은 올라간다")
    func probabilityIsMonotonic() {
        let high = run(base(target: 500_000_000), volatilityBP: 1_500).successProbability!
        let low = run(base(target: 300_000_000), volatilityBP: 1_500).successProbability!
        #expect(low >= high)
    }

    @Test("기간이나 경로가 없으면 빈 결과를 돌려준다")
    func degenerate() {
        var single = base()
        single.endDate = single.startDate
        #expect(run(single, volatilityBP: 1_500).bands.isEmpty)

        #expect(run(base(), volatilityBP: 1_500, paths: 0).paths == 0)
    }

    @Test("밴드는 연말마다 하나씩, 마지막 시점으로 끝난다")
    func bandCadence() {
        let result = run(base(years: 10), volatilityBP: 1_500, paths: 50)
        // 2026~2035 연말 열 개 + 마지막 2036-01-01.
        #expect(result.bands.count == 11)
        #expect(result.bands.last?.date == date("2036-01-01"))
        #expect(result.bands.map(\.date) == result.bands.map(\.date).sorted())
    }

    @Test("잔고는 음수로 내려가지 않는다")
    func neverNegative() {
        // 변동성 80%면 어떤 달은 −100% 를 넘겨 찍는다. 빚으로 굴러가면 안 된다.
        var draining = base(years: 20, start: 10_000_000, monthly: 0)
        draining.cashEvents = [
            CashEventInput(date: date("2030-01-01"), amount: Money(-50_000_000, currency: .krw),
                           label: "주택 구입")
        ]
        let result = run(draining, volatilityBP: 8_000)
        for band in result.bands {
            #expect(band.p10.minorUnits >= 0)
        }
    }
}
