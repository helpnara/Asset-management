import Core
import CoreData
import SwiftUI

struct PlanView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.managedObjectContext) private var context
    // 계획의 가정은 **가구 전체**에 걸린다. 한 사람이 기대수익률을 바꾸면
    // 모두의 궤적이 바뀌므로 관리자만 고친다 (docs/09-family-sharing.md).
    @Environment(\.canManageHousehold) private var canManageHousehold
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched private var holdings: [Holding]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @State private var editingEvent: CashEvent?
    /// 방금 만든 것의 id — 편집 시트의 `취소` 가 지운다 (104번).
    @State private var newIDs: Set<UUID> = []
    @State private var editingIncome: IncomeStream?
    @State private var pendingIncomeDelete: IndexSet?
    @State private var pendingEventDelete: IndexSet?
    /// 마지막으로 끝난 계산 (153번). 화면은 이 값을 그리기만 한다.
    @State private var projected: ProjectionResult?
    /// 굴리는 중인가. 숫자를 지우지 않고 흐리게 둔 채 `반영 중` 을 곁들인다 —
    /// 빈칸이 되면 "고장났나" 로 읽힌다.
    @State private var isProjecting = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    form(plan)
                } else {
                    ProgressView().task { _ = Plan.current(in: context) }
                }
            }
            .confirmsDelete($pendingIncomeDelete, title: "이 수입을 삭제할까요?",
                            message: "은퇴 후 궤적에서 이 수입이 빠집니다. 되돌릴 수 없습니다.") { offsets in
                for index in offsets where incomes.indices.contains(index) {
                    context.delete(incomes[index])
                }
            }
            .confirmsDelete($pendingEventDelete, title: "이 목돈 이벤트를 삭제할까요?",
                            message: "궤적에서 이 목돈이 빠집니다. 되돌릴 수 없습니다.") { offsets in
                for index in offsets where cashEvents.indices.contains(index) {
                    context.delete(cashEvents[index])
                }
            }
            // 계획의 어떤 값이든 달라지면 수정 시각을 찍는다. 화면을 열기만
            // 해서는 안 찍힌다 — 지문이 실제로 달라져야 한다.
            .onChange(of: plans.first?.editFingerprint) { previous, current in
                guard let previous, let current else { return }   // 첫 진입은 변경이 아니다
                plans.first?.touch()
                // 무엇을 고쳤는지도 남긴다 (docs/08-feedback.md 29번).
                // **값은 안 남긴다** — 이력이 금액 목록이 되면 안 된다.
                ChangeLogger.planChanged(labels: Plan.changedLabels(from: previous, to: current),
                                         in: context)
            }
            .navigationTitle("계획")
            .navigationBarTitleDisplayMode(.inline)
            // 금액 칸의 `만 · 억 · 완료` 띠 (152번 3-1).
            .moneyKeyboardBar()
            .sheet(item: $editingEvent, onDismiss: { newIDs.removeAll() }) {
                CashEventEditView(event: $0, isNew: newIDs.contains($0.id))
            }
            .sheet(item: $editingIncome, onDismiss: { newIDs.removeAll() }) {
                IncomeStreamEditView(stream: $0, isNew: newIDs.contains($0.id))
            }
        }
    }

    /// `2026. 9. 7. 오후 2:31` 처럼. 날짜만으로는 "오늘 고쳤나" 를 못 본다.
    private static func updatedText(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private func form(_ plan: Plan) -> some View {
        let bind = plan.bindings
        // 계산에 들어가는 값들을 **값 타입 하나로** 뽑는다 (153번). 이게 달라질
        // 때만 다시 굴린다. `ProjectionInput` 은 `Hashable` 이라 `.task(id:)` 의
        // 열쇠로 그대로 쓸 수 있고, `Sendable` 이라 주 스레드 밖으로 건네도 된다 —
        // 관리 객체를 넘기지 않는다는 규칙(CLAUDE.md)을 그대로 지킨다.
        let input = plan.projectionInput(from: currentBalance, cashEvents: cashEvents,
                                         incomes: incomes, members: members)
        return Form {
            if !canManageHousehold {
                Section { ReadOnlyNote(text: "계획의 가정은 관리자만 고칠 수 있습니다.") }
            }

            // **보러 온 것을 맨 위에** (152번 2-6). 예전에는 수립일 · 마지막 수정이
            // 맨 위였다 — 열자마자 보이는 것이 메타 정보였다. 요약은 잠그지 않는다:
            // 참가자가 이 화면에서 가장 보고 싶은 것이다.
            Section("이대로 가면") {
                summary(plan)
            }

            Section("기간") {
                if canManageHousehold {
                    Stepper(value: bind.retirementYear, in: currentYear...(currentYear + 60)) {
                        // Text("...\(정수)...") 는 로케일 숫자 포맷을 적용해 "2,049년" 이 된다.
                        // 연도에는 자릿수 구분을 넣지 않는다.
                        Text(verbatim: "은퇴 목표 \(plan.retirementYear)년")
                    }
                } else {
                    readOnlyRow("은퇴 목표", "\(plan.retirementYear)년")
                }
                LabeledContent("남은 기간", value: "\(plan.yearsToRetirement)년")
            }

            Section {
                if canManageHousehold {
                    Toggle("4% 규칙으로 자동 계산", isOn: bind.targetIsAuto)
                }
                if plan.targetIsAuto {
                    // **자동일 때는 고칠 수 없다** (154번 사용자 요청). 손으로 넣은
                    // 값과 계산한 값이 섞이면 어느 쪽이 맞는지 알 수 없게 된다.
                    LabeledContent("은퇴 목표 금액") {
                        Text(plan.autoTargetAmount.map { Won.abbreviated($0, suffix: "원") } ?? "—")
                            .font(.figure(15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    // 수식은 **목표 금액 바로 아래 작은 글씨로**.
                    Text(plan.autoTargetFormula)
                        .font(.figure(10.5))
                        .foregroundStyle(Color.faint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if canManageHousehold {
                    MoneyField(title: "은퇴 목표 금액", minorUnits: bind.targetAmountMinor)
                } else {
                    readOnlyMoney("은퇴 목표 금액", plan.targetAmountMinor)
                }
            } footer: {
                if plan.targetIsAuto {
                    Text("은퇴 뒤 한 해에 쓸 돈을 **인출률로 나눈** 값입니다. 쓸 돈은 아래 **은퇴 이후** 에서 넣고, 인출률은 더보기 → 자산 진단 → 진단 기준에서 정합니다. 스위치를 끄면 직접 넣을 수 있습니다.")
                } else {
                    Text("0으로 두면 목표선을 그리지 않습니다. 스위치를 켜면 은퇴 뒤 쓸 돈으로 계산해 넣습니다.")
                }
            }

            Section {
                if plan.usesMemberContributions {
                    LabeledContent("매월 적립 합계") {
                        Text(Won.abbreviated(
                            plan.effectiveMonthlyContribution(members: members), suffix: "원"))
                            .font(.figure(15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                } else if canManageHousehold {
                    MoneyField(title: "매월 적립", minorUnits: bind.monthlyContributionMinor)
                } else {
                    readOnlyMoney("매월 적립", plan.monthlyContributionMinor)
                }
                percentRow("적립액 연 증가율", bind.contributionGrowthBP, range: 0...1000, step: 50)
                if canManageHousehold {
                    Toggle("구성원별로 나눠 넣기", isOn: bind.usesMemberContributions)
                } else {
                    readOnlyRow("구성원별로 나눠 넣기",
                                plan.usesMemberContributions ? "켬" : "끔")
                }
            } footer: {
                Text(plan.usesMemberContributions
                     ? "아래에서 사람마다 넣습니다. 합계가 궤적에 쓰입니다."
                     : "가구 전체의 월 적립 합계입니다. 사람마다 나누고 싶으면 위 스위치를 켜세요.")
            }

            if plan.usesMemberContributions { memberContributionSection }

            Section {
                percentRow("연 기대수익률", bind.annualReturnBP, range: 0...1500, step: 25)
                percentRow("은퇴 후 기대수익률", bind.postRetirementReturnBP, range: 0...1500, step: 25)
                percentRow("물가상승률", bind.inflationBP, range: 0...800, step: 25)
            } footer: {
                Text("은퇴 뒤에는 안전자산 비중이 커져 수익률이 내려갑니다. 은퇴 후 기대수익률은 보수적으로 5%가 기본입니다. 입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다.")
            }

            Section {
                percentRow("채권", bind.bondReturnBP, range: 0...1000, step: 25)
                percentRow("금 · 원자재", bind.commodityReturnBP, range: 0...1000, step: 25)
                percentRow("예적금 · 연금보험 · 예수금", bind.lowYieldReturnBP, range: 0...800, step: 10)
                percentRow("부동산", bind.realEstateReturnBP, range: 0...800, step: 25)
            } header: {
                Text("자산군별 기대수익률")
            } footer: {
                // 기본값이 곧 대부분 사용자의 값이다 (D6, 사용자 결정 09-11). 무엇에
                // 무엇이 걸리는지를 여기서 다 말해야 손댈 사람이 손댄다.
                Text("위 기대수익률은 **주식 · ETF 에만** 걸립니다. 투자 계좌 안에 있어도 채권·금·예수금은 여기 값으로 따로 굴리고, 전월세보증금과 받을 돈은 **자라지 않는 것으로** 봅니다. 계좌마다 다르면 자산 탭에서 그 계좌에 직접 적을 수 있습니다 — 그 값이 이깁니다.")
            }

            retirementSection(plan)
            incomeSection(plan)
            cashEventSection

            // 계획은 한 번 세우고 계속 다듬는 것이라 제목이 필요 없다.
            // 언제 세웠고 언제 갱신했는지만 있으면 된다 (docs/08-feedback.md 21번).
            // **맨 아래로 내렸다** (152번 2-6) — 자주 보는 값이 아니다.
            Section {
                if canManageHousehold {
                    DatePicker("최초 계획 수립일",
                               selection: Binding(get: { plan.startedOn ?? .now },
                                                  set: { plan.startedOn = $0 }),
                               displayedComponents: .date)
                } else {
                    readOnlyRow("최초 계획 수립일",
                                (plan.startedOn ?? .now).formatted(date: .numeric, time: .omitted))
                }
                LabeledContent("마지막 수정") {
                    Text(plan.updatedAt.map(Self.updatedText) ?? "아직 없음")
                        .font(.scaled(13))
                        .foregroundStyle(plan.updatedAt == nil ? Color.muted : Color.bodyText)
                }
            } header: {
                Text("기록")
            } footer: {
                Text("수정할 때마다 자동으로 기록됩니다. 1페이지에 들어가는 제목·기준 시점·맨 밑 한 줄은 **더보기 → 내보내기 → 1페이지 문서 설정**에서 고칩니다.")
            }
        }
        // **굴리는 것은 화면 그리기 밖에서** (153번). 손잡이를 돌릴 때마다
        // 궤적 전체를 주 스레드에서 다시 계산하느라, 누른 것과 숫자가 바뀌는
        // 사이가 벌어졌다 — 안 되었나 싶어 또 누르게 되던 것이 이 때문이다.
        .task(id: input) { await project(input) }
        // **자동 목표는 칸에 실제로 써 넣는다** (154번). 궤적 · 진단 · 1페이지 ·
        // 시뮬레이션이 전부 `targetAmountMinor` 를 읽으므로, 계산만 하고 안 쓰면
        // 다른 화면이 옛 숫자를 보여 준다. 값이 같으면 쓰지 않는다 — 안 그러면
        // 화면을 열기만 해도 `마지막 수정` 이 찍힌다.
        .onChange(of: autoTargetKey(plan), initial: true) { _, _ in
            guard plan.targetIsAuto, let auto = plan.autoTargetAmount else { return }
            if plan.targetAmountMinor != auto.minorUnits {
                plan.targetAmountMinor = auto.minorUnits
            }
        }
    }

    /// 자동 목표에 들어가는 값들. 이 중 하나라도 달라지면 목표 금액을 다시 쓴다.
    private func autoTargetKey(_ plan: Plan) -> String {
        "\(plan.targetIsAuto)-\(plan.monthlySpendingMinor)-\(plan.annualHobbyMinor)-\(plan.annualMedicalMinor)-\(plan.withdrawalRateBP)"
    }

    /// 한 번 굴린다. `.task(id:)` 가 값이 또 달라지면 이 작업을 **취소**하므로,
    /// 맨 앞의 기다림이 곧 연타 접기다 — 손잡이를 다섯 칸 돌려도 계산은 한 번이다.
    private func project(_ input: ProjectionInput) async {
        isProjecting = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        // 값(`Sendable`)만 건넨다. 관리 객체는 이 경계를 넘지 않는다.
        let result = await Task.detached(priority: .userInitiated) {
            Projection.run(input)
        }.value
        guard !Task.isCancelled else { return }
        projected = result
        isProjecting = false
    }

    /// 구성원별 적립. 합계 하나로도 궤적은 똑같이 그려진다 — 나누는 이유는
    /// "누가 얼마를 넣고 있는가"가 가족이 함께 보는 화면에서 의미를 갖기 때문이다.
    private var memberContributionSection: some View {
        Section {
            ForEach(members) { member in
                let bind = member.bindings
                if canManageHousehold {
                    MoneyField(title: member.name.isEmpty ? "이름 없음" : member.name,
                               minorUnits: bind.monthlyContributionMinor)
                } else {
                    readOnlyMoney(member.name.isEmpty ? "이름 없음" : member.name,
                                  member.monthlyContributionMinor)
                }
            }
            if members.isEmpty {
                Text("자산 탭에서 구성원을 먼저 추가하세요.")
                    .font(.scaled(12))
                    .foregroundStyle(Color.muted)
            }
        } header: {
            Text("구성원별 월 적립")
        } footer: {
            Text("여기 합계가 궤적과 진단의 저축률에 쓰입니다. 아이 계좌에 넣는 돈도 가구 적립입니다 — 빼놓으면 저축률이 실제보다 낮게 나옵니다.")
        }
    }

    /// 은퇴 이후. 이걸 넣어야 궤적이 은퇴에서 멈추지 않고 이어진다.
    private func retirementSection(_ plan: Plan) -> some View {
        let bind = plan.bindings
        return Section {
            if canManageHousehold {
                MoneyField(title: "은퇴 후 월 생활비", minorUnits: bind.monthlySpendingMinor)
                // **해마다 한 번 크게 쓰는 돈** (154번). 월 생활비에 녹여 넣으라고
                // 하면 12로 나누다 틀린다. 목표 금액 자동 계산이 이 둘을 쓴다.
                MoneyField(title: "연 취미 · 여행", minorUnits: bind.annualHobbyMinor)
                MoneyField(title: "연 병원비", minorUnits: bind.annualMedicalMinor)
                Stepper(value: bind.horizonYear,
                        in: (plan.retirementYear + 1)...(plan.retirementYear + 50)) {
                    Text(verbatim: "\(plan.horizonYear)년까지 본다")
                }
            } else {
                readOnlyMoney("은퇴 후 월 생활비", plan.monthlySpendingMinor)
                readOnlyMoney("연 취미 · 여행", plan.annualHobbyMinor)
                readOnlyMoney("연 병원비", plan.annualMedicalMinor)
                readOnlyRow("보는 기간", "\(plan.horizonYear)년까지")
            }
        } header: {
            Text("은퇴 이후")
        } footer: {
            // **취미 · 병원비가 어디에 걸리고 어디에 안 걸리는지** 를 적는다.
            // 목표 금액에는 들어가고 궤적의 인출에는 아직 안 들어간다 — 둘을
            // 함께 올릴지는 따로 정하기로 했다 (154번 3).
            Text("생활비를 넣으면 궤적이 은퇴에서 멈추지 않고 인출 구간까지 이어집니다. 0으로 두면 은퇴 시점에서 끝납니다. 오늘 돈 기준으로 적으세요 — 물가는 앱이 태웁니다.\n\n**연 취미 · 여행**과 **연 병원비**는 해마다 한 번 나가는 돈입니다. 지금은 위의 **은퇴 목표 금액** 계산에만 쓰이고, 궤적의 인출에는 월 생활비만 씁니다.")
        }
    }

    private func incomeSection(_ plan: Plan) -> some View {
        Section {
            ForEach(incomes) { stream in
                // 보기 전용이면 버튼으로 두지 않는다 — 눌러도 아무 일이 없는
                // 버튼은 잠긴 화면이 아니라 고장 난 화면으로 읽힌다.
                if canManageHousehold {
                    Button { editingIncome = stream } label: { incomeRow(stream) }
                } else {
                    incomeRow(stream)
                }
            }
            .onDelete(perform: canManageHousehold
                      ? { (offsets: IndexSet) in pendingIncomeDelete = offsets } : nil)

            if canManageHousehold {
                Button {
                    let stream = IncomeStream(context: context, startYear: plan.retirementYear, sortIndex: incomes.count)
                    newIDs.insert(stream.id)
                    editingIncome = stream
                } label: {
                    Label("은퇴 후 소득 추가", systemImage: "plus")
                        .font(.scaled(12.5))
                }
            }
        } header: {
            Text("은퇴 후 소득")
        } footer: {
            Text("국민연금 · 퇴직연금 · 개인연금 · 임대소득. 생활비에서 이만큼을 빼고 나머지를 자산에서 꺼냅니다. 물가연동 여부가 30년 뒤 결과를 절반으로 가릅니다.")
        }
    }

    private func incomeRow(_ stream: IncomeStream) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(stream.label.isEmpty ? "이름 없음" : stream.label)
                    .font(.scaled(13))
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
            Text(Won.abbreviated(stream.monthlyAmount, suffix: "원"))
                .font(.figure(12.5, weight: .medium))
                .foregroundStyle(Color.ink)
        }
    }

    private var cashEventSection: some View {
        Section {
            ForEach(cashEvents) { event in
                if canManageHousehold {
                    Button { editingEvent = event } label: { cashEventRow(event) }
                } else {
                    cashEventRow(event)
                }
            }
            .onDelete(perform: canManageHousehold
                      ? { (offsets: IndexSet) in pendingEventDelete = offsets } : nil)

            if canManageHousehold {
                Button {
                    let event = CashEvent(context: context, date: .now, label: "", sortIndex: cashEvents.count)
                    newIDs.insert(event.id)
                    editingEvent = event
                } label: {
                    Label("목돈 이벤트 추가", systemImage: "plus")
                        .font(.scaled(12.5))
                }
            }
        } header: {
            Text("목돈 이벤트")
        } footer: {
            Text("퇴직금 유입, 전월세보증금 전환, 주택 구입처럼 큰 자금이 한 번에 움직이는 시점입니다. 23년 복리에서는 목돈 하나가 결과를 크게 바꿉니다.")
        }
    }

    private func cashEventRow(_ event: CashEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.label.isEmpty ? "이름 없음" : event.label)
                    .font(.scaled(13))
                    .foregroundStyle(Color.ink)
                HStack(spacing: 5) {
                    Text(event.date, format: .dateTime.year().month())
                        .font(.scaled(10))
                        .foregroundStyle(Color.faint)
                    if event.isAlreadyReflected {
                        StatusBadge(text: "이미 반영됨")
                    }
                }
            }
            Spacer()
            Text((event.isInflow ? "+" : "−")
                 + Won.grouped(abs(event.amountMinor)))
                .font(.figure(12.5, weight: .medium))
                .foregroundStyle(event.isAlreadyReflected ? Color.faint
                                 : (event.isInflow ? Color.gain : Color.loss))
        }
    }

    @ViewBuilder
    private func summary(_ plan: Plan) -> some View {
        // **은퇴 시점의 값이다, 궤적의 끝이 아니다.** 은퇴 후 생활비를 넣으면
        // 궤적이 지평선(예: 92세)까지 이어지므로 `last` 는 30년 인출한 뒤의
        // 잔고다. 현황판·진단·1페이지·시뮬레이션은 전부 은퇴 시점을 읽는데
        // 이 화면만 끝값을 읽어 "2049년 예상" 이 다른 숫자였다 (51번).
        if let result = projected,
           let end = result.point(inYear: plan.retirementYear) ?? result.last {
            Group {
                LabeledContent {
                    Text(Won.abbreviated(end.nominal, suffix: "원"))
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                } label: {
                    Text(verbatim: "\(plan.retirementYear)년 예상")
                }
                LabeledContent("오늘 돈 기준") {
                    Text(Won.abbreviated(end.real, suffix: "원"))
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
            // 새 값이 오기 전까지 **옛 값을 흐리게 남긴다**. 지우면 화면이
            // 깜빡이고, 그 깜빡임이 "고장났나" 로 읽힌다.
            .opacity(isProjecting ? 0.4 : 1)

            if isProjecting { recalculatingRow }
        } else {
            // 첫 계산. 아직 보여 줄 옛 값이 없다.
            recalculatingRow
        }
    }

    private var recalculatingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("반영 중")
                .font(.scaled(12))
                .foregroundStyle(Color.muted)
            Spacer(minLength: 0)
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

    /// **여기서 잠근다.** 네 곳에서 쓰이므로 부르는 쪽마다 적으면 하나를
    /// 빠뜨리고, 빠뜨린 하나로 참가자가 가구 전체의 가정을 바꿀 수 있다.
    ///
    /// **`.disabled` 로는 부족했다.** 손대지 못하게는 하지만 화면이 그대로라
    /// (스크린샷이 픽셀 단위로 같았다) 잠긴 줄을 알 수가 없다. 그래서 아예
    /// 스테퍼를 안 세우고 값만 적는다 — 다른 화면에서 버튼을 안 세운 것과 같다.
    @ViewBuilder
    private func percentRow(_ title: String, _ value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int) -> some View {
        if canManageHousehold {
            Stepper(value: value, in: range, step: step) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(percentText(value.wrappedValue, step: step))
                        .font(.figure(14, weight: .medium))
                        .foregroundStyle(Color.ink)
                }
            }
        } else {
            readOnlyRow(title, percentText(value.wrappedValue, step: step))
        }
    }

    private func percentText(_ value: Int, step: Int) -> String {
        step % 100 == 0
            ? "\(PercentFormatter.integer(Decimal(value) / 10_000))%"
            : "\(PercentFormatter.oneDecimal(Decimal(value) / 10_000))%"
    }

    /// 보기 전용일 때 `MoneyField` 자리에 세우는 줄. `원` 까지 같이 적는다 —
    /// 안 그러면 한 화면에 `4,100,000 원` 과 `4,100,000` 이 섞인다.
    private func readOnlyMoney(_ title: String, _ minorUnits: Int) -> some View {
        readOnlyRow(title, Won.grouped(minorUnits) + " 원")
    }

    /// 보기 전용일 때 입력칸 자리에 세우는 줄. 값은 그대로 읽힌다.
    private func readOnlyRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.figure(15, weight: .medium))
                .foregroundStyle(Color.bodyText)
        }
    }
}
