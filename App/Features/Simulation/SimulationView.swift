import Core
import SwiftData
import SwiftUI

/// What-if — "월 30만원 더 넣으면 얼마나 달라지나"에 답하는 화면.
///
/// 계획 탭이 **가정을 정하는 곳**이라면 여기는 **가정을 흔들어 보는 곳**이다.
/// 손잡이를 돌려도 저장되지 않는다. 마음에 들면 [계획에 반영]을 눌러야 넘어간다.
/// 이 분리가 없으면 무심코 돌린 슬라이더가 계획을 덮어쓴다.
struct SimulationView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [Plan]
    @Query private var holdings: [Holding]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Query(sort: \Member.sortIndex) private var members: [Member]

    @State private var knobs: Knobs?
    @State private var outcome: SimulationOutcome?
    @State private var isCalculating = false

    /// 다시 계산해야 하는지 판단하는 키. 둘 다 값 타입이라 그대로 비교된다.
    struct RunKey: Hashable, Sendable {
        var baseline: ProjectionInput
        var knobs: Knobs
    }

    /// 사용자가 돌리는 손잡이. 전부 값 타입이라 계산 스레드로 그대로 넘어간다.
    struct Knobs: Hashable, Sendable {
        var monthlyMinor: Int
        var retirementYear: Int
        var returnBP: Int
        /// 연 변동성. 0이면 밴드가 한 줄로 붙는다.
        var volatilityBP: Int
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    content(plan)
                } else {
                    ProgressView().task { _ = Plan.current(in: context) }
                }
            }
            .background(Color.surface.opacity(0.5))
            .navigationTitle("시뮬레이션")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func content(_ plan: Plan) -> some View {
        let baseline = plan.projectionInput(from: currentBalance, cashEvents: cashEvents, incomes: incomes, members: members)
        let current = knobs ?? Knobs(plan)

        ScrollView {
            VStack(spacing: 14) {
                headline(plan, current)
                chartCard(plan, changed: current != Knobs(plan))
                knobCard(plan, current)
                spreadCard
                actionRow(plan, current)
                disclaimer
            }
            .padding(14)
        }
        .task(id: RunKey(baseline: baseline, knobs: current)) {
            // 손잡이를 돌릴 때마다 이전 계산은 자동으로 취소된다.
            // 잔고가 바뀌어도(주간 점검 직후) 다시 돈다 — 그래서 baseline 도 키에 넣는다.
            await recalculate(baseline: baseline, knobs: current)
        }
        .onAppear { if knobs == nil { knobs = Knobs(plan) } }
    }

    // MARK: - 헤드라인

    @ViewBuilder
    private func headline(_ plan: Plan, _ knobs: Knobs) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "\(knobs.retirementYear)년 예상")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.muted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(outcome.map { KoreanAmountFormatter.abbreviated($0.expected, suffix: "원") } ?? "—")
                    .font(.figure(26, weight: .bold))
                    .foregroundStyle(Color.ink)
                if isCalculating {
                    ProgressView().controlSize(.mini)
                }
            }

            if let outcome, outcome.delta.minorUnits != 0 {
                Text(deltaText(outcome.delta))
                    .font(.figure(12.5, weight: .medium))
                    .foregroundStyle(outcome.delta.minorUnits > 0 ? Color.gain : Color.loss)
            } else {
                Text("계획 그대로입니다. 아래 손잡이를 돌려 보세요.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.faint)
            }

            if let outcome {
                Text("오늘 돈으로 \(KoreanAmountFormatter.abbreviated(outcome.expectedReal, suffix: "원"))")
                    .font(.figure(11.5))
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private func deltaText(_ delta: Money) -> String {
        let size = KoreanAmountFormatter.abbreviated(
            Money(minorUnits: abs(delta.minorUnits), currency: .krw), suffix: "원")
        return "계획보다 " + size + (delta.minorUnits > 0 ? " 많다" : " 적다")
    }

    // MARK: - 차트

    private func chartCard(_ plan: Plan, changed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 손잡이를 안 돌렸으면 계획선은 예상선과 완전히 겹친다.
            // 그 위에 점선을 덧그리면 실선이 점선처럼 보여서 차트가 망가진다.
            SimulationChart(
                bands: outcome?.bands ?? [],
                baseline: changed ? (outcome?.baseline ?? []) : [],
                targetMinor: plan.targetAmountMinor
            )
            legend(plan, changed: changed)
            if plan.targetAmountMinor > 0 {
                Divider().overlay(Color.rule).padding(.vertical, 2)
                successGauge
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func legend(_ plan: Plan, changed: Bool) -> some View {
        HStack(spacing: 12) {
            legendItem(color: Color.dad, label: "예상", dashed: false)
            legendItem(color: Color.dad.opacity(0.35), label: "10~90%", dashed: false)
            if changed {
                legendItem(color: Color.faint, label: "계획 그대로", dashed: true)
            }
            Spacer(minLength: 0)
            if plan.targetAmountMinor > 0 {
                Text("목표 " + KoreanAmountFormatter.compact(plan.targetAmount))
                    .font(.figure(9.5))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: dashed ? 6 : 12, height: 2.5)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.muted)
        }
    }

    // MARK: - 성공 확률

    @ViewBuilder
    private var successGauge: some View {
        if let outcome, let probability = outcome.successProbability {
            let percent = Int((probability * 100).rounded())
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("목표 도달 확률")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.bodyText)
                    Spacer()
                    Text(verbatim: "\(percent)%")
                        .font(.figure(20, weight: .bold))
                        .foregroundStyle(percent >= 70 ? Color.gain
                                         : (percent >= 40 ? Color.ink : Color.loss))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.rule)
                        Capsule()
                            .fill(percent >= 70 ? Color.gain
                                  : (percent >= 40 ? Color.dad : Color.loss))
                            .frame(width: geometry.size.width * CGFloat(probability))
                    }
                }
                .frame(height: 6)

                // 확률 하나만 크게 띄우면 "70%면 괜찮은 건가?" 로 끝난다.
                // 무엇을 센 숫자인지 같이 적는다. 횟수는 상수로 적지 않고
                // 실제로 굴린 경로 수를 그대로 쓴다 — 둘이 어긋나면 거짓말이 된다.
                Text(hitCountText(probability, of: outcome.paths))
                    .font(.figure(10.5))
                    .foregroundStyle(Color.faint)
            }
        }
    }

    private func hitCountText(_ probability: Double, of paths: Int) -> String {
        let hits = Int((probability * Double(paths)).rounded())
        return KoreanAmountFormatter.grouped(paths) + "번 굴려 "
            + KoreanAmountFormatter.grouped(hits) + "번 목표를 넘겼습니다"
    }

    // MARK: - 손잡이

    private func knobCard(_ plan: Plan, _ knobs: Knobs) -> some View {
        let binding = Binding(get: { self.knobs ?? knobs }, set: { self.knobs = $0 })
        return VStack(spacing: 16) {
            slider(
                title: "매월 적립",
                value: binding.monthlyMinor,
                range: 0...max(5_000_000, plan.monthlyContributionMinor * 2),
                step: 100_000,
                baselineValue: plan.monthlyContributionMinor,
                display: { KoreanAmountFormatter.abbreviated(Money(minorUnits: $0, currency: .krw), suffix: "원") }
            )
            slider(
                title: "은퇴 연도",
                value: binding.retirementYear,
                range: (currentYear + 1)...(currentYear + 50),
                step: 1,
                baselineValue: plan.retirementYear,
                display: { "\($0)년" }
            )
            slider(
                title: "연 기대수익률",
                value: binding.returnBP,
                range: 0...1500,
                step: 25,
                baselineValue: plan.annualReturnBP,
                display: { "\(PercentFormatter.oneDecimal(Decimal($0) / 10000))%" }
            )
            slider(
                title: "연 변동성",
                value: binding.volatilityBP,
                range: 0...3000,
                step: 100,
                baselineValue: Knobs.defaultVolatilityBP,
                display: { "\(PercentFormatter.oneDecimal(Decimal($0) / 10000))%" }
            )
        }
        .padding(14)
        .background(cardBackground)
    }

    private func slider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        baselineValue: Int,
        display: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.figure(14, weight: .semibold))
                    .foregroundStyle(value.wrappedValue == baselineValue ? Color.ink : Color.dad)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int(($0 / Double(step)).rounded()) * step }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(Color.dad)
        }
    }

    // MARK: - 분포

    @ViewBuilder
    private var spreadCard: some View {
        if let outcome {
            VStack(spacing: 0) {
                spreadRow("잘 안 풀리면 (하위 10%)", outcome.low, Color.loss)
                Divider().overlay(Color.rule)
                spreadRow("예상", outcome.expected, Color.ink)
                Divider().overlay(Color.rule)
                spreadRow("잘 풀리면 (상위 10%)", outcome.high, Color.gain)
                if outcome.hasDrawdown {
                    Divider().overlay(Color.rule)
                    depletionRow(outcome)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(cardBackground)
        }
    }

    /// 은퇴 후 인출까지 그릴 때만 나온다. 추정할 수 없으면 만들지 않는다.
    private func depletionRow(_ outcome: SimulationOutcome) -> some View {
        HStack {
            Text("자산 고갈")
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
            Spacer()
            if let year = outcome.depletionYear {
                Text(verbatim: "\(year)년")
                    .font(.figure(14, weight: .medium))
                    .foregroundStyle(Color.loss)
            } else {
                Text("끝까지 안 바닥남")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gain)
            }
        }
        .padding(.vertical, 10)
    }

    private func spreadRow(_ label: String, _ amount: Money, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
            Spacer()
            Text(KoreanAmountFormatter.abbreviated(amount, suffix: "원"))
                .font(.figure(14, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.vertical, 10)
    }

    // MARK: - 반영 · 되돌리기

    @ViewBuilder
    private func actionRow(_ plan: Plan, _ knobs: Knobs) -> some View {
        let changed = knobs != Knobs(plan)
        HStack(spacing: 10) {
            Button {
                self.knobs = Knobs(plan)
            } label: {
                Text("되돌리기")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.bordered)
            .tint(Color.muted)

            Button {
                plan.monthlyContributionMinor = knobs.monthlyMinor
                plan.retirementYear = knobs.retirementYear
                plan.annualReturnBP = knobs.returnBP
            } label: {
                Text("계획에 반영")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ink)
        }
        .disabled(!changed)
        .opacity(changed ? 1 : 0.45)
    }

    private var disclaimer: some View {
        // 변동성은 밴드에만 쓰고 계획에는 저장하지 않는다. 이걸 적어 두지 않으면
        // "반영을 눌렀는데 변동성이 안 남는다"는 오해가 생긴다.
        Text("입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다. 밴드는 변동성을 넣고 여러 번 굴린 결과이고, 변동성은 계획에 저장되지 않습니다.")
            .font(.system(size: 10.5))
            .foregroundStyle(Color.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.rule, lineWidth: 1)
            )
    }

    // MARK: - 계산

    /// `ProjectionInput` · `Knobs` 는 값 타입이라 그대로 넘어간다.
    /// `@Model` 은 여기 들어오지 않는다 (CLAUDE.md 규칙).
    private func recalculate(baseline: ProjectionInput, knobs: Knobs) async {
        // 슬라이더를 끄는 동안 매 단계마다 1,000번씩 굴리지는 않는다.
        // 손을 멈추기 전의 계산은 `.task(id:)` 가 취소해 준다.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calendar = Calendar.current
        let adjusted = Self.adjust(baseline, with: knobs, calendar: calendar)
        let volatility = Ratio(basisPoints: knobs.volatilityBP)
        let retirementYear = knobs.retirementYear

        let computed = await Task.detached(priority: .userInitiated) {
            SimulationOutcome.make(baseline: baseline, adjusted: adjusted,
                                   volatility: volatility, retirementYear: retirementYear,
                                   calendar: calendar)
        }.value

        guard !Task.isCancelled else { return }
        outcome = computed
    }

    /// 은퇴 연도 손잡이는 **은퇴 시점**을 옮긴다. 지평선(`endDate`)은 그만큼 같이
    /// 밀어서 인출 구간의 길이를 유지한다. 은퇴만 5년 미루고 지평선을 그대로 두면
    /// "5년 더 벌고 5년 덜 쓴다"가 되어 손잡이가 두 가지 일을 하게 된다.
    static func adjust(_ input: ProjectionInput, with knobs: Knobs,
                       calendar: Calendar = .current) -> ProjectionInput {
        var adjusted = input
        adjusted.monthlyContribution = Money(minorUnits: knobs.monthlyMinor, currency: .krw)
        adjusted.annualReturn = Ratio(basisPoints: knobs.returnBP)
        adjusted.retirementDate = Plan.endDate(retirementYear: knobs.retirementYear,
                                               notBefore: input.startDate, calendar: calendar)

        let drawdownMonths = calendar.dateComponents([.month],
                                                     from: input.retirementDate,
                                                     to: input.endDate).month ?? 0
        adjusted.endDate = drawdownMonths > 0
            ? (calendar.date(byAdding: .month, value: drawdownMonths, to: adjusted.retirementDate)
               ?? adjusted.retirementDate)
            : adjusted.retirementDate
        return adjusted
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var currentBalance: Money {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw).netWorth
    }
}

extension SimulationView.Knobs {
    /// 주식 위주 포트폴리오의 대략적인 연 변동성. 밴드의 기본 폭이 된다.
    static let defaultVolatilityBP = 1_500

    init(_ plan: Plan) {
        self.init(
            monthlyMinor: plan.monthlyContributionMinor,
            retirementYear: plan.retirementYear,
            returnBP: plan.annualReturnBP,
            volatilityBP: Self.defaultVolatilityBP
        )
    }
}

/// 계산 결과. `Sendable` 값만 담아 계산 스레드에서 그대로 건너온다.
struct SimulationOutcome: Sendable {
    var bands: [SimulationChart.Band]
    var baseline: [SimulationChart.LinePoint]
    var low: Money
    /// 변동성을 빼고 계산한 값. 계획 탭이 보여주는 숫자와 같아야 한다 —
    /// 탭마다 다른 "예상"이 나오면 어느 쪽도 믿지 않게 된다.
    var expected: Money
    var high: Money
    var expectedReal: Money
    /// 계획 그대로일 때와의 차이. 이 숫자 하나가 What-if 의 답이다.
    var delta: Money
    var successProbability: Double?
    /// 몇 번 굴렸는지. 화면의 "n번 중 m번" 문구가 이걸 읽는다.
    var paths: Int
    /// 잔고가 0이 되는 해. nil 이면 지평선까지 버틴다. 인출을 가정하지 않으면
    /// 계산하지 않으므로 그때도 nil 이다.
    var depletionYear: Int?
    /// 인출 구간을 그리고 있는가. 이게 false 면 고갈 줄을 아예 보여주지 않는다.
    var hasDrawdown: Bool

    static func make(
        baseline input: ProjectionInput,
        adjusted: ProjectionInput,
        volatility: Ratio,
        retirementYear: Int,
        calendar: Calendar
    ) -> SimulationOutcome {
        let deterministic = Projection.run(adjusted, calendar: calendar)
        let plain = Projection.run(input, calendar: calendar)
        let monteCarlo = MonteCarlo.run(
            MonteCarloInput(base: adjusted, annualVolatility: volatility),
            calendar: calendar
        )

        // 밴드의 가운데 선은 몬테카를로의 p50 이 아니라 결정론적 궤적이다.
        // p50 은 변동성 때문에 예상선보다 아래에 놓이는데, 화면의 큰 숫자와
        // 차트의 선이 어긋나면 그건 버그로 읽힌다. 폭만 시뮬레이션에서 가져온다.
        var expectedByDate: [Date: Int] = [:]
        for point in deterministic.points { expectedByDate[point.date] = point.nominal.minorUnits }

        let bands = monteCarlo.bands.map { band in
            SimulationChart.Band(
                date: band.date,
                low: band.p10.minorUnits,
                mid: expectedByDate[band.date] ?? band.p50.minorUnits,
                high: band.p90.minorUnits
            )
        }

        // 계획선은 밴드와 같은 리듬으로 성기게 뽑는다. 매달 찍으면 선이 두꺼워지기만 한다.
        let baselinePoints = plain.points
            .reduce(into: [SimulationChart.LinePoint]()) { result, point in
                let year = calendar.component(.year, from: point.date)
                let entry = SimulationChart.LinePoint(date: point.date,
                                                     minor: point.nominal.minorUnits)
                if let last = result.last, calendar.component(.year, from: last.date) == year {
                    result[result.count - 1] = entry
                } else {
                    result.append(entry)
                }
            }

        // 헤드라인은 **은퇴 시점** 값이다. 인출 구간까지 그리기 시작하면서
        // `last` 가 은퇴 후 30년 뒤 잔고가 됐다 — 그걸 "2049년 예상"이라고
        // 보여주면 통째로 다른 숫자다.
        let end = deterministic.point(inYear: retirementYear, calendar: calendar)?.nominal
            ?? deterministic.last?.nominal ?? adjusted.startingBalance
        let planYear = calendar.component(.year, from: input.retirementDate)
        let planEnd = plain.point(inYear: planYear, calendar: calendar)?.nominal
            ?? plain.last?.nominal ?? input.startingBalance

        return SimulationOutcome(
            bands: bands,
            baseline: baselinePoints,
            low: monteCarlo.bands.last?.p10 ?? end,
            expected: end,
            high: monteCarlo.bands.last?.p90 ?? end,
            expectedReal: deterministic.last?.real ?? end,
            delta: end - planEnd,
            successProbability: monteCarlo.successProbability,
            paths: monteCarlo.paths,
            depletionYear: deterministic.depletion.map { calendar.component(.year, from: $0) },
            hasDrawdown: adjusted.endDate > adjusted.retirementDate
        )
    }
}
