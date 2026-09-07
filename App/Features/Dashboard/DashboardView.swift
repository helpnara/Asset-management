import Core
import SwiftData
import SwiftUI

struct DashboardView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var sessions: [ReviewSession]
    @Query(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Query private var plans: [Plan]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query private var accounts: [Account]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Query(sort: \UserMilestone.year) private var userMilestones: [UserMilestone]

    /// CI 스크린샷이 점검 화면도 찍을 수 있도록 실행 인자로 바로 열 수 있게 한다.
    @State private var isReviewing = ProcessInfo.processInfo.arguments.contains("-startReview")
    @State private var completedToShow: ReviewSession?
    /// 기간은 궤적 차트가 들고 있다 — 구성원 궤적과 같은 값을 나눠 쓴다
    /// (docs/08-feedback.md 31번). 여기서는 범례를 그릴지 판단하려고 읽는다.
    @AppStorage(TrajectoryChart.spanKey) private var chartSpan: TrajectoryChart.Span = .all

    private var rollup: Rollup {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Rectangle().fill(Color.ink).frame(height: 2)

                    if members.isEmpty {
                        emptyState
                    } else {
                        hero
                        Rectangle().fill(Color.rule).frame(height: 1)
                            .padding(.horizontal, 20)
                        weeklyBar
                        roadmap
                        lifeEvents
                        trajectory
                        diagnosticsStrip
                        alerts
                        memberBreakdown
                        totals
                    }
                }
            }
            .fullScreenCover(item: $completedToShow) { session in
                ReviewCompleteView(session: session)
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $isReviewing) {
                WeeklyReviewView()
            }
            .task {
                // 완료 화면은 11번 눌러야 도달하므로 CI 스크린샷이 찍을 수 없다.
                // 실행 인자로 마지막 점검 결과를 바로 띄운다.
                if ProcessInfo.processInfo.arguments.contains("-showReviewComplete") {
                    completedToShow = sessions
                        .filter(\.isComplete)
                        .max { $0.weekAnchor < $1.weekAnchor }
                }
            }
        }
    }

    private var completedAnchors: [Date] {
        sessions.filter(\.isComplete).map(\.weekAnchor)
    }

    private var streak: Int {
        ReviewWeek.streak(completedAnchors: completedAnchors, asOf: .now)
    }

    private var didReviewThisWeek: Bool {
        completedAnchors.contains(ReviewWeek.anchor(for: .now))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("느 린 부 자 의 기 록").eyebrowStyle()
            Text("우리 가족 노후자금 준비")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("가 족 총 자 산").eyebrowStyle().padding(.bottom, 7)
            Text(Won.abbreviated(rollup.netWorth, suffix: "원"))
                .font(.figure(38, weight: .semibold))
                .foregroundStyle(Color.ink)
            if !rollup.liabilities.isZero {
                Text("자산 \(Won.abbreviated(rollup.assets)) · 부채 \(Won.abbreviated(rollup.liabilities))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    /// 루틴으로 되돌리는 자리. 헤더 바로 아래, 궤적보다 위 (설계 2.2.0).
    private var weeklyBar: some View {
        HStack(spacing: 10) {
            Image(systemName: didReviewThisWeek ? "checkmark.circle" : "calendar")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(didReviewThisWeek ? Color.gain : Color.ink)

            VStack(alignment: .leading, spacing: 2) {
                Text(weeklyTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                Text(weeklySubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)

            if !didReviewThisWeek {
                Button {
                    isReviewing = true
                } label: {
                    Text("지금 입력")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                }
            }
        }
        .padding(13)
        .background(Color.surface)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var weeklyTitle: String {
        if didReviewThisWeek { return "이번 주 점검 완료" }
        let days = ReviewWeek.daysUntilReview(from: .now)
        return days == 0 ? "오늘이 점검일입니다" : "이번 주 점검 · 토요일까지 D-\(days)"
    }

    private var weeklySubtitle: String {
        if streak == 0 { return "매주 토요일 오전에 알려드립니다" }
        return "\(streak)주 연속 기록 중"
    }

    /// 경고는 목록 안에 묻으면 스크롤해야 보인다. 현황판 위쪽에 올린다 (설계 2.2.4).
    @ViewBuilder
    private var alerts: some View {
        let violations = holdings.filter(\.violatesPFIC)
        if !violations.isEmpty {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.loss)
                VStack(alignment: .leading, spacing: 2) {
                    Text("세적 제약 — 한국 상장 ETF \(violations.count)건")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text(violations.map(\.name).joined(separator: " · ") + " · PFIC 대상")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Color.alertSoft)
            .padding(.top, 12)
        }
    }

    // MARK: - 로드맵

    /// **뼈대 여섯 칸으로 고정한다.** 지금 · 자산 2배 · 수익 > 적립금 ·
    /// 수익 > 연봉 · 목표 달성 · 은퇴.
    ///
    /// 예전에는 사용자 마일스톤까지 같은 줄에 섞었다. 그것만 개수 제한이 없어서
    /// 인생 이벤트가 늘수록 로드맵이 길어지고 읽기 어려워졌다
    /// (docs/08-feedback.md 5번). 인생 이벤트는 아래 순자산 궤적의 x축에 찍는다.
    ///
    /// **오지 않는 칸도 지우지 않는다.** 목표를 못 넘기면 `목표 달성` 이 없고
    /// `자산 2배` 는 이미 지났을 수 있는데, 그때마다 칸이 사라지면 뼈대가
    /// 흔들려서 매번 다른 그림이 된다. 자리를 지키고 상태만 적는다.
    private var roadmapStops: [RoadmapStrip.Stop] {
        guard let plan, let projection else { return [] }
        let thisYear = Calendar.current.component(.year, from: .now)

        var stops: [RoadmapStrip.Stop] = [
            .init(year: thisYear, amount: rollup.netWorth, label: "지금", isNow: true, isGoal: false)
        ]

        // 뼈대의 순서는 **의미의 순서**다. 연도로 정렬하지 않는다 — 그러면
        // 달성 여부에 따라 칸이 앞뒤로 튀어 매번 다른 그림이 된다.
        for kind in [MilestoneKind.doubled, .returnsExceedContribution,
                     .returnsExceedSalary, .targetReached] {
            if let hit = projection.milestone(kind) {
                stops.append(.init(year: hit.year, amount: hit.balance,
                                   label: kind.label, isNow: false, isGoal: false,
                                   state: hit.year <= thisYear ? .passed : .ahead))
            } else {
                stops.append(.init(year: nil, amount: nil, label: kind.label,
                                   isNow: false, isGoal: false, state: .never))
            }
        }

        // 마지막 정거장은 **은퇴 시점**이다. 인출 구간까지 그리기 시작하면서
        // years.last 가 은퇴 후 30년 뒤가 됐다 — 거기에 "은퇴" 라벨을 붙이면 틀린다.
        if let atRetirement = projection.years.last(where: { $0.year <= plan.retirementYear }) {
            stops.append(.init(year: atRetirement.year, amount: atRetirement.endBalance,
                               label: "은퇴", isNow: false, isGoal: true))
        }
        return stops
    }

    /// 인생 이벤트(아이 대학 입학, 전세 만기 …)를 궤적의 x축 눈금으로 옮겼다.
    /// 로드맵에 섞으면 개수가 늘수록 뼈대가 길어진다 (docs/08-feedback.md 5번).
    private var milestoneMarks: [TrajectoryChart.EventMark] {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: .now)
        return userMilestones.compactMap { milestone in
            guard milestone.year >= thisYear,
                  let date = calendar.date(from: DateComponents(year: milestone.year, month: 1, day: 1))
            else { return nil }
            return TrajectoryChart.EventMark(
                date: date,
                label: milestone.label.isEmpty ? "마일스톤" : milestone.label
            )
        }
    }

    /// 바닥나는 해. 정거장으로 넣지 않고 **머리글 옆 경고**로 뺀다 —
    /// 여섯 칸의 뼈대를 흔들지 않으면서, 일어난다면 가장 무거운 한 점이다.
    private var depletionYear: Int? {
        projection?.depletion.map { Calendar.current.component(.year, from: $0) }
    }

    @ViewBuilder
    private var roadmap: some View {
        if roadmapStops.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("전체 자산 로드맵",
                              trailing: plan.map { "\($0.yearsToRetirement)년 남음" } ?? "")
                if let depletionYear {
                    Text("\(String(depletionYear))년에 바닥납니다")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.loss)
                        .padding(.bottom, 6)
                }
                RoadmapStrip(stops: roadmapStops)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - 궤적

    private var plan: Plan? { plans.first }

    private var projection: ProjectionResult? {
        plan?.projection(from: rollup.netWorth, cashEvents: cashEvents, incomes: incomes, members: members)
    }

    /// 과거는 매주 적어 넣은 스냅샷, 미래는 예측. 같은 축에 잇는다.
    private var trajectoryPoints: [TrajectoryChart.Point] {
        var result = snapshots.map {
            TrajectoryChart.Point(date: $0.weekAnchor, minor: $0.netWorthMinor, series: .actual)
        }
        // 예측선은 오늘에서 출발한다. 과거 마지막 점과 이어 붙어 끊겨 보이지 않는다.
        //
        // **은퇴까지만 그린다** (docs/08-feedback.md 33번). 생활비를 적어 두면
        // 예측이 은퇴 뒤 35년까지 이어지는데, 선형 축에서 그 끝(수백억)에 축을
        // 맞추면 지금 자산이 바닥에 붙어 보이지 않는다. 은퇴 이후는 진단과
        // 시뮬레이션이 답하는 질문이고, 이 그래프의 질문은 은퇴까지다.
        if let projection {
            let limit = plan.map {
                Plan.endDate(retirementYear: $0.retirementYear,
                             notBefore: Calendar.current.startOfDay(for: .now))
            }
            let monthly = projection.points.enumerated()
                .filter { $0.offset % 3 == 0 || $0.offset == projection.points.count - 1 }
                .map { $0.element }
                .filter { limit.map { end in $0.date <= end } ?? true }
                .map { TrajectoryChart.Point(date: $0.date,
                                             minor: $0.nominal.minorUnits,
                                             series: .projected) }
            result.append(contentsOf: monthly)
        }
        return result
    }

    // MARK: - 인생 이벤트

    /// 직접 찍은 마일스톤을 **글로 보여 준다** (docs/08-feedback.md 32번).
    ///
    /// 지금까지는 궤적 차트의 세로 눈금 하나가 전부였다. 7.5pt 회색 글씨라
    /// 사실상 안 보였고, 기간을 좁히면 아예 사라졌다 — 사용자가 "입력한 값이
    /// 어디에 쓰이는지 모르겠다" 고 한 것이 정확한 지적이다.
    ///
    /// **그때의 예상 자산과 그 사람의 나이를 함께 적는다.** 연도만으로는
    /// 그 해가 얼마나 먼지, 무엇을 뜻하는지 몸으로 느껴지지 않는다.
    @ViewBuilder
    private var lifeEvents: some View {
        // 한 번만 계산해서 나눠 쓴다. 이 값은 궤적 예측을 한 번 돌린다.
        let events = upcomingEvents
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("인생 이벤트",
                              trailing: userMilestones.count > events.count
                                  ? "가까운 \(events.count)개" : "")
                VStack(spacing: 0) {
                    ForEach(events, id: \.id) { event in
                        lifeEventRow(event)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func lifeEventRow(_ event: LifeEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(event.year)")
                    .font(.figure(14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(event.yearsAway == 0 ? "올해" : "\(event.yearsAway)년 뒤")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
            }
            .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(event.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                    if let owner = event.ownerName {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.member(event.colorIndex))
                                .frame(width: 6, height: 6)
                            Text(event.age.map { "\(owner) \($0)세" } ?? owner)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.muted)
                        }
                    }
                }
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            if let amount = event.projected {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Won.compact(amount))
                        .font(.figure(13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("그때 예상")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.faint)
                }
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule).frame(height: 0.5)
        }
    }

    struct LifeEvent: Identifiable {
        let id: UUID
        let year: Int
        let yearsAway: Int
        let label: String
        let note: String
        let ownerName: String?
        let age: Int?
        let colorIndex: Int
        let projected: Money?
    }

    /// 앞으로 올 것 셋. 지난 것은 적지 않는다 — 현황판은 앞을 보는 화면이다.
    private var upcomingEvents: [LifeEvent] {
        let thisYear = Calendar.current.component(.year, from: .now)
        // 예측은 한 번만 돌린다. 줄마다 부르면 세 번 돈다.
        let result = projection
        return userMilestones
            .filter { $0.year >= thisYear }
            .sorted { $0.year < $1.year }
            .prefix(3)
            .map { milestone in
                let owner = milestone.memberID.flatMap { id in members.first { $0.id == id } }
                return LifeEvent(
                    id: milestone.id,
                    year: milestone.year,
                    yearsAway: milestone.year - thisYear,
                    label: milestone.label.isEmpty ? "이름 없음" : milestone.label,
                    note: milestone.note,
                    ownerName: owner.map { $0.name.isEmpty ? "이름 없음" : $0.name },
                    age: owner.map { max(0, milestone.year - $0.birthYear) },
                    colorIndex: owner?.colorIndex ?? 0,
                    projected: result?.point(inYear: milestone.year)?.nominal
                )
            }
    }

    @ViewBuilder
    private var trajectory: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("순자산 궤적")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            // 기간 선택은 차트가 들고 있다. 창을 좁히면 목표선도 차트가 스스로 뺀다.
            TrajectoryChart(
                points: trajectoryPoints,
                today: Calendar.current.startOfDay(for: .now),
                targetMinor: plan?.targetAmountMinor ?? 0,
                events: milestoneMarks
            )
            .padding(.horizontal, 16)

            HStack(spacing: 14) {
                legend(color: .ink, dashed: false, label: "실제 기록")
                legend(color: .dad, dashed: true, label: "예측")
                if chartSpan == .all, let target = plan?.targetAmount, !target.isZero {
                    legend(color: .ink.opacity(0.55), dashed: true,
                           label: "목표 \(Won.compact(target))")
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let summary = trajectorySummary {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.bodyText)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                Text(assumptionLine)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.faint)
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
            }
        }
    }

    private func legend(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(dashed ? Color.clear : color)
                .overlay {
                    if dashed {
                        Rectangle().fill(color).frame(width: 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 14, height: 2)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.muted)
        }
    }

    private var trajectorySummary: String? {
        guard let plan, plan.monthlyContributionMinor > 0,
              let end = projection?.point(inYear: plan.retirementYear) ?? projection?.last
        else { return nil }
        // 한 줄에 들어가야 읽힌다. 상세 자릿수는 계획 탭에서 본다.
        let nominal = Won.compact(end.nominal)
        let real = Won.compact(end.real)
        var line = "이대로 가면 \(String(plan.retirementYear))년에 \(nominal) · 오늘 돈으로 \(real)"
        if plan.targetAmountMinor > 0 {
            let ratio = Decimal(end.nominal.minorUnits) / Decimal(plan.targetAmountMinor)
            line += " · 목표의 \(PercentFormatter.integer(ratio))%"
        }
        if let depletion = projection?.depletion {
            line += " · \(String(Calendar.current.component(.year, from: depletion)))년 고갈"
        }
        return line
    }

    private var assumptionLine: String {
        guard let plan else { return "" }
        return "연 \(PercentFormatter.oneDecimal(plan.annualReturn.fraction))% · 물가 \(PercentFormatter.oneDecimal(plan.inflation.fraction))% 가정 · 입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다"
    }

    private var memberBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("구성원", trailing: "\(members.count)명")
            Rectangle().fill(Color.rule).frame(height: 1)
            ForEach(members) { member in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text("\(member.roleNote.isEmpty ? "" : member.roleNote + " · ")\(member.age)세")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.faint)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(Won.abbreviated(rollup.byMember[member.id] ?? .zero(.krw)))
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(Color.member(member.colorIndex))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                Rectangle().fill(Color.rule).frame(height: 1)
            }
        }
    }

    /// 진단 요약. 숫자 셋만 보여 주고 자세한 것은 진단 화면으로 넘긴다.
    ///
    /// 현황판에 여섯 규칙을 다 펼치면 매주 보는 화면이 무거워진다.
    /// 여기서는 "할 일이 있는가"만 답한다.
    @ViewBuilder
    private var diagnosticsStrip: some View {
        if let plan = plans.first {
            let result = Diagnostics.run(plan.diagnosticsInput(
                rollup: rollup,
                accounts: accounts,
                projection: plan.projection(from: rollup.netWorth, cashEvents: cashEvents,
                                            incomes: incomes, members: members),
                members: members
            ))

            Button {
                AppRoute.shared.wantsDiagnostics = true
                AppRoute.shared.selectedTab = RootView.Tab.more
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("자산 진단")
                    Rectangle().fill(Color.rule).frame(height: 1)

                    HStack(spacing: 14) {
                        diagnosisTally("조치", result.count(.act), .loss)
                        diagnosisTally("주의", result.count(.watch), Color.dad)
                        diagnosisTally("지킴", result.count(.pass), .gain)
                        if result.count(.unknown) > 0 {
                            diagnosisTally("입력 필요", result.count(.unknown), .faint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.faint)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    if let first = result.sorted.first, first.status != .pass {
                        Text(first.title + " — " + first.headline)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 20)
            }
            .buttonStyle(.plain)
        }
    }

    private func diagnosisTally(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(count)")
                .font(.figure(15, weight: .bold))
                .foregroundStyle(count > 0 ? color : Color.faint)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.muted)
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("가족 합계")
            Rectangle().fill(Color.rule).frame(height: 1)
            totalRow("투자자산", rollup.investable)
            totalRow("총자산", rollup.assets, emphasized: true)
            if !rollup.liabilities.isZero {
                totalRow("부채", rollup.liabilities)
            }
            countrySplit
        }
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var countrySplit: some View {
        let korea = rollup.countryShare("KR")
        let usa = rollup.countryShare("US")
        if let korea, let usa, !rollup.investable.isZero {
            VStack(spacing: 7) {
                // 둘을 함께 반올림해 합이 100 이 되게 한다. 따로 반올림하면
                // `한국 30 / 미국 71` 같은 줄이 나온다.
                HStack {
                    let split = Allocation.integerPercents([korea, usa])
                    Text("한국 \(split[0])")
                    Spacer()
                    Text("미국 \(split[1])")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Color.muted)

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.mom)
                            .frame(width: proxy.size.width * fraction(korea))
                        Rectangle().fill(Color.dad)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private func fraction(_ value: Decimal) -> CGFloat {
        CGFloat(NSDecimalNumber(decimal: value).doubleValue)
    }


    private func totalRow(_ label: String, _ money: Money, emphasized: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? Color.ink : Color.muted)
                Spacer()
                Text(Won.full(money))
                    .font(.figure(12.5, weight: emphasized ? .bold : .medium))
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            Rectangle().fill(Color.rule).frame(height: 1)
        }
    }

    private func sectionHeader(_ title: String, trailing: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    /// 빈 상태는 다음 한 걸음을 **누를 수 있게** 둔다 (설계 2.7).
    /// "자산 탭으로 가세요"라고 적어만 두면 거기서 멈추는 사람이 생긴다.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("아직 등록된 자산이 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("구성원을 먼저 추가하세요.\n한 명 · 한 종목만 넣어도 합계가 그려집니다.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .lineSpacing(4)

            Button {
                AppRoute.shared.wantsNewMember = true
                AppRoute.shared.selectedTab = RootView.Tab.assets
            } label: {
                Label("구성원 추가하기", systemImage: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.onInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ink)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.top, 40)
    }
}
