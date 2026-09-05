import Core
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var sessions: [ReviewSession]
    @Query(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Query private var plans: [Plan]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]

    /// CI 스크린샷이 점검 화면도 찍을 수 있도록 실행 인자로 바로 열 수 있게 한다.
    @State private var isReviewing = ProcessInfo.processInfo.arguments.contains("-startReview")
    @State private var completedToShow: ReviewSession?
    @AppStorage("dashboard.chartRange") private var chartRange: ChartRange = .retirement

    /// 은퇴까지만 보면 과거가 눌리고, 최근만 보면 큰 그림이 사라진다. 둘 다 필요하다.
    enum ChartRange: String, CaseIterable, Identifiable {
        case recent = "최근 3년"
        case retirement = "은퇴까지"
        var id: String { rawValue }
    }

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
                        trajectory
                        alerts
                        memberBreakdown
                        totals
                    }
                }
            }
            .fullScreenCover(item: $completedToShow) { session in
                ReviewCompleteView(session: session)
            }
            .background(Color.white)
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
            Text(KoreanAmountFormatter.abbreviated(rollup.netWorth, suffix: "원"))
                .font(.figure(38, weight: .semibold))
                .foregroundStyle(Color.ink)
            if !rollup.liabilities.isZero {
                Text("자산 \(KoreanAmountFormatter.abbreviated(rollup.assets)) · 부채 \(KoreanAmountFormatter.abbreviated(rollup.liabilities))")
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
            .background(Color(hex: 0xFDF7F8))
            .padding(.top, 12)
        }
    }

    // MARK: - 로드맵

    /// 오늘 · 자동 판정된 교차점 · 은퇴 목표를 연도순으로 늘어놓는다.
    private var roadmapStops: [RoadmapStrip.Stop] {
        guard let plan, let projection else { return [] }
        var stops: [RoadmapStrip.Stop] = [
            .init(year: Calendar.current.component(.year, from: .now),
                  amount: rollup.netWorth, label: "지금", isNow: true, isGoal: false)
        ]

        for milestone in projection.milestones where milestone.year > stops[0].year {
            stops.append(.init(year: milestone.year, amount: milestone.balance,
                               label: milestone.kind.label, isNow: false, isGoal: false))
        }

        if let end = projection.years.last {
            stops.append(.init(year: end.year, amount: end.endBalance,
                               label: "은퇴", isNow: false, isGoal: true))
        }

        // 같은 해에 여러 개가 걸리면 앞의 것만 남긴다.
        var seen = Set<Int>()
        return stops.sorted { $0.year < $1.year }.filter { seen.insert($0.year).inserted }
    }

    @ViewBuilder
    private var roadmap: some View {
        if roadmapStops.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("전체 자산 로드맵",
                              trailing: plan.map { "\($0.yearsToRetirement)년 남음" } ?? "")
                RoadmapStrip(stops: roadmapStops)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - 궤적

    private var plan: Plan? { plans.first }

    private var projection: ProjectionResult? {
        plan?.projection(from: rollup.netWorth, cashEvents: cashEvents)
    }

    /// 과거는 매주 적어 넣은 스냅샷, 미래는 예측. 같은 축에 잇는다.
    private var trajectoryPoints: [TrajectoryChart.Point] {
        var result = snapshots.map {
            TrajectoryChart.Point(date: $0.weekAnchor, minor: $0.netWorthMinor, series: .actual)
        }
        // 예측선은 오늘에서 출발한다. 과거 마지막 점과 이어 붙어 끊겨 보이지 않는다.
        if let projection {
            let monthly = projection.points.enumerated()
                .filter { $0.offset % 3 == 0 || $0.offset == projection.points.count - 1 }
                .map { TrajectoryChart.Point(date: $0.element.date,
                                             minor: $0.element.nominal.minorUnits,
                                             series: .projected) }
            result.append(contentsOf: monthly)
        }
        return result
    }

    /// 최근 3년을 볼 때는 목표선(수십억)을 그리지 않는다. 그리면 나머지가 다 눌린다.
    private var visiblePoints: [TrajectoryChart.Point] {
        guard chartRange == .recent else { return trajectoryPoints }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard
            let from = calendar.date(byAdding: .year, value: -3, to: today),
            let to = calendar.date(byAdding: .year, value: 3, to: today)
        else { return trajectoryPoints }
        return trajectoryPoints.filter { $0.date >= from && $0.date <= to }
    }

    @ViewBuilder
    private var trajectory: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("순자산 궤적")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Picker("기간", selection: $chartRange) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            TrajectoryChart(
                points: visiblePoints,
                today: Calendar.current.startOfDay(for: .now),
                targetMinor: chartRange == .retirement ? (plan?.targetAmountMinor ?? 0) : 0
            )
            .padding(.horizontal, 16)

            HStack(spacing: 14) {
                legend(color: .ink, dashed: false, label: "실제 기록")
                legend(color: .dad, dashed: true, label: "예측")
                if chartRange == .retirement, let target = plan?.targetAmount, !target.isZero {
                    legend(color: .ink.opacity(0.55), dashed: true,
                           label: "목표 \(KoreanAmountFormatter.compact(target))")
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
        guard let plan, let end = projection?.last, plan.monthlyContributionMinor > 0 else { return nil }
        // 한 줄에 들어가야 읽힌다. 상세 자릿수는 계획 탭에서 본다.
        let nominal = KoreanAmountFormatter.compact(end.nominal)
        let real = KoreanAmountFormatter.compact(end.real)
        var line = "이대로 가면 \(String(plan.retirementYear))년에 \(nominal) · 오늘 돈으로 \(real)"
        if plan.targetAmountMinor > 0 {
            let ratio = Decimal(end.nominal.minorUnits) / Decimal(plan.targetAmountMinor)
            line += " · 목표의 \(PercentFormatter.oneDecimal(ratio))%"
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
                    Text(KoreanAmountFormatter.abbreviated(rollup.byMember[member.id] ?? .zero(.krw)))
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(Color.member(member.colorIndex))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                Rectangle().fill(Color.rule).frame(height: 1)
            }
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
                HStack {
                    Text("한국 \(PercentFormatter.oneDecimal(korea))")
                    Spacer()
                    Text("미국 \(PercentFormatter.oneDecimal(usa))")
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
                Text(KoreanAmountFormatter.full(money))
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
                AppRoute.shared.selectedTab = RootView.Tab.assets
            } label: {
                Label("구성원 추가하기", systemImage: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
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
