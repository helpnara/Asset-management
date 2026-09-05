import Core
import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [Plan]
    @Query private var holdings: [Holding]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @State private var editingEvent: CashEvent?
    @State private var editingIncome: IncomeStream?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    form(plan)
                } else {
                    ProgressView().task { _ = Plan.current(in: context) }
                }
            }
            .navigationTitle("계획")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingEvent) { CashEventEditView(event: $0) }
            .sheet(item: $editingIncome) { IncomeStreamEditView(stream: $0) }
        }
    }

    private func form(_ plan: Plan) -> some View {
        @Bindable var plan = plan
        return Form {
            Section("계획 제목") {
                TextField("우리 가족 노후자금 준비", text: $plan.title)
            }

            Section {
                MoneyField(title: "매월 적립", minorUnits: $plan.monthlyContributionMinor)
                percentRow("적립액 연 증가율", $plan.contributionGrowthBP, range: 0...1000, step: 50)
            } footer: {
                Text("가구 전체의 월 적립 합계입니다. 구성원별 배분은 다음 단계에서 나눕니다.")
            }

            Section {
                percentRow("연 기대수익률", $plan.annualReturnBP, range: 0...1500, step: 25)
                percentRow("물가상승률", $plan.inflationBP, range: 0...800, step: 25)
            } footer: {
                Text("입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다.")
            }

            Section("기간") {
                Stepper(value: $plan.retirementYear, in: currentYear...(currentYear + 60)) {
                    // Text("...\(정수)...") 는 로케일 숫자 포맷을 적용해 "2,049년" 이 된다.
                    // 연도에는 자릿수 구분을 넣지 않는다.
                    Text(verbatim: "은퇴 목표 \(plan.retirementYear)년")
                }
                LabeledContent("남은 기간", value: "\(plan.yearsToRetirement)년")
            }

            Section {
                MoneyField(title: "은퇴 목표 금액", minorUnits: $plan.targetAmountMinor)
            } footer: {
                Text("0으로 두면 목표선을 그리지 않습니다.")
            }

            retirementSection(plan)
            incomeSection(plan)
            cashEventSection

            Section("이대로 가면") {
                summary(plan)
            }

        }
    }

    /// 은퇴 이후. 이걸 넣어야 궤적이 은퇴에서 멈추지 않고 이어진다.
    private func retirementSection(_ plan: Plan) -> some View {
        @Bindable var plan = plan
        return Section {
            MoneyField(title: "은퇴 후 월 생활비", minorUnits: $plan.monthlySpendingMinor)
            Stepper(value: $plan.horizonYear,
                    in: (plan.retirementYear + 1)...(plan.retirementYear + 50)) {
                Text(verbatim: "\(plan.horizonYear)년까지 본다")
            }
        } header: {
            Text("은퇴 이후")
        } footer: {
            Text("생활비를 넣으면 궤적이 은퇴에서 멈추지 않고 인출 구간까지 이어집니다. 0으로 두면 은퇴 시점에서 끝납니다. 오늘 돈 기준으로 적으세요 — 물가는 앱이 태웁니다.")
        }
    }

    private func incomeSection(_ plan: Plan) -> some View {
        Section {
            ForEach(incomes) { stream in
                Button {
                    editingIncome = stream
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stream.label.isEmpty ? "이름 없음" : stream.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(verbatim: stream.endYear > 0
                                     ? "\(stream.startYear)~\(stream.endYear)년"
                                     : "\(stream.startYear)년부터 종신")
                                    .font(.figure(10))
                                    .foregroundStyle(Color.faint)
                                if !stream.isInflationLinked {
                                    StatusBadge(text: "물가 미연동")
                                }
                            }
                        }
                        Spacer()
                        Text(KoreanAmountFormatter.abbreviated(stream.monthlyAmount, suffix: "원"))
                            .font(.figure(12.5, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets where incomes.indices.contains(index) {
                    context.delete(incomes[index])
                }
            }

            Button {
                let stream = IncomeStream(startYear: plan.retirementYear, sortIndex: incomes.count)
                context.insert(stream)
                editingIncome = stream
            } label: {
                Label("은퇴 후 소득 추가", systemImage: "plus")
                    .font(.system(size: 12.5))
            }
        } header: {
            Text("은퇴 후 소득")
        } footer: {
            Text("국민연금 · 퇴직연금 · 개인연금 · 임대소득. 생활비에서 이만큼을 빼고 나머지를 자산에서 꺼냅니다. 물가연동 여부가 30년 뒤 결과를 절반으로 가릅니다.")
        }
    }

    private var cashEventSection: some View {
        Section {
            ForEach(cashEvents) { event in
                Button {
                    editingEvent = event
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.label.isEmpty ? "이름 없음" : event.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(event.date, format: .dateTime.year().month())
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.faint)
                                if event.isAlreadyReflected {
                                    StatusBadge(text: "이미 반영됨")
                                }
                            }
                        }
                        Spacer()
                        Text((event.isInflow ? "+" : "−")
                             + KoreanAmountFormatter.grouped(abs(event.amountMinor)))
                            .font(.figure(12.5, weight: .medium))
                            .foregroundStyle(event.isAlreadyReflected ? Color.faint
                                             : (event.isInflow ? Color.gain : Color.loss))
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets where cashEvents.indices.contains(index) {
                    context.delete(cashEvents[index])
                }
            }

            Button {
                let event = CashEvent(date: .now, label: "", sortIndex: cashEvents.count)
                context.insert(event)
                editingEvent = event
            } label: {
                Label("목돈 이벤트 추가", systemImage: "plus")
                    .font(.system(size: 12.5))
            }
        } header: {
            Text("목돈 이벤트")
        } footer: {
            Text("퇴직금 유입, 전세보증금 전환, 주택 구입처럼 큰 자금이 한 번에 움직이는 시점입니다. 23년 복리에서는 목돈 하나가 결과를 크게 바꿉니다.")
        }
    }

    @ViewBuilder
    private func summary(_ plan: Plan) -> some View {
        let result = plan.projection(from: currentBalance, cashEvents: cashEvents, incomes: incomes)
        if let end = result.last {
            LabeledContent {
                Text(KoreanAmountFormatter.abbreviated(end.nominal, suffix: "원"))
                    .font(.figure(15, weight: .semibold))
                    .foregroundStyle(Color.ink)
            } label: {
                Text(verbatim: "\(plan.retirementYear)년 예상")
            }
            LabeledContent("오늘 돈 기준") {
                Text(KoreanAmountFormatter.abbreviated(end.real, suffix: "원"))
                    .font(.figure(13))
                    .foregroundStyle(Color.muted)
            }
            if plan.targetAmountMinor > 0 {
                LabeledContent("목표 달성률") {
                    Text(achievement(end.nominal, plan.targetAmountMinor))
                        .font(.figure(13, weight: .medium))
                        .foregroundStyle(end.nominal.minorUnits >= plan.targetAmountMinor
                                         ? Color.gain : Color.loss)
                }
            }
            depletionRow(plan, result)
        }
    }

    /// 이 앱에서 가장 무거운 한 줄이다.
    ///
    /// 그래서 **추정할 수 없으면 만들지 않는다.** 은퇴 후 생활비를 넣지 않으면
    /// 인출 자체를 가정하지 않으므로 이 줄도 나오지 않는다.
    @ViewBuilder
    private func depletionRow(_ plan: Plan, _ result: ProjectionResult) -> some View {
        if plan.monthlySpendingMinor > 0 {
            if let depletion = result.depletion {
                let year = Calendar.current.component(.year, from: depletion)
                LabeledContent("자산 고갈") {
                    Text(verbatim: "\(year)년 (은퇴 \(year - plan.retirementYear)년 뒤)")
                        .font(.figure(13, weight: .medium))
                        .foregroundStyle(Color.loss)
                }
            } else {
                LabeledContent("자산 고갈") {
                    Text(verbatim: "\(plan.horizonYear)년까지 안 바닥남")
                        .font(.figure(13, weight: .medium))
                        .foregroundStyle(Color.gain)
                }
            }
        }
    }

    private func achievement(_ value: Money, _ target: Int) -> String {
        guard target > 0 else { return "—" }
        let ratio = Decimal(value.minorUnits) / Decimal(target)
        return "\(PercentFormatter.oneDecimal(ratio))%"
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var currentBalance: Money {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw).netWorth
    }

    private func percentRow(_ title: String, _ value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(PercentFormatter.oneDecimal(Decimal(value.wrappedValue) / 10000))%")
                    .font(.figure(14, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}
