import Core
import CoreData
import SwiftUI

struct DashboardView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false
    // 주간 점검은 **숫자를 적어 넣는** 화면이라 보기 전용이면 열 이유가 없다.
    @Environment(\.canEdit) private var canEdit
    @Environment(\.self) private var environment
    /// 당겨서 새로고침의 결과 한 줄 (73번).
    @State private var refreshNote: String?

    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched private var holdings: [Holding]
    @Fetched private var sessions: [ReviewSession]
    @Fetched(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched private var accounts: [Account]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \UserMilestone.year) private var userMilestones: [UserMilestone]
    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var diary: [DiaryEntry]
    @Fetched(sort: \ChangeLog.at, order: .reverse) private var logs: [ChangeLog]

    /// CI 스크린샷이 점검 화면도 찍을 수 있도록 실행 인자로 바로 열 수 있게 한다.
    @State private var isReviewing = ProcessInfo.processInfo.arguments.contains("-startReview")
    @State private var completedToShow: ReviewSession?
    /// 로드맵 정거장을 누르면 그 시점의 분해 시트 (85번).
    @State private var selectedStop: RoadmapStrip.Stop?
    /// 기간은 궤적 차트가 들고 있다 — 구성원 궤적과 같은 값을 나눠 쓴다
    /// (docs/08-feedback.md 31번). 여기서는 범례를 그릴지 판단하려고 읽는다.
    @AppStorage(TrajectoryChart.spanKey) private var chartSpan: TrajectoryChart.Span = .retirement
    /// 카드 순서와 숨김 (83번, C6). 여기서 읽어야 설정을 바꾼 순간 다시 그려진다.
    @AppStorage(DashboardCard.orderKey) private var cardOrderRaw = ""
    @AppStorage(DashboardCard.hiddenKey) private var hiddenCardsRaw = ""

    private var visibleCards: [DashboardCard] {
        let hidden = DashboardCard.hidden(from: hiddenCardsRaw)
        return DashboardCard.order(from: cardOrderRaw).filter { !hidden.contains($0) }
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
                        // 오늘 한 줄은 자산이 없어도 쓴다 (마지막 묶음 1).
                        DiaryCard()
                        // "아직 없는 것" 과 "아직 안 온 것" 은 다른 화면이다 (53번).
                        if SyncLoadingHint.shouldShow {
                            SyncLoadingHint()
                        } else {
                            emptyState
                        }
                    } else {
                        // **순서는 사용자가 정한다** (83번). 기본은 목·실·감이 맨 위 —
                        // 매일 여는 첫 화면에서 처음 만나는 것이 오늘 한 줄이어야
                        // 매일 쓴다 (마지막 묶음 1).
                        ForEach(visibleCards) { card in
                            cardView(card)
                        }
                    }
                }
            }
            .fullScreenCover(item: $completedToShow) { session in
                ReviewCompleteView(session: session)
            }
            .sheet(item: $selectedStop) { stop in
                if let plan, let projection {
                    RoadmapStopSheet(stop: stop, plan: plan, projection: projection,
                                     members: members, rollup: rollup)
                }
            }
            // 앱의 한 가지 바탕 (35번). 예전에는 여기만 `canvas` 라
            // 다른 탭과 검정이 달랐다.
            .background(Color.ground)
            .syncRefreshable(note: $refreshNote)
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

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        // **소제목은 하나의 꼴이다** (89번). 카드마다 제목 글꼴이 달랐다 —
        // 목·실·감은 카드 안에, 총자산은 자간 넓힌 작은 글자로. 전부
        // `sectionHeader` 로 세운다.
        switch card {
        case .diary:
            sectionHeader("오늘의 목 · 실 · 감", trailing: DiaryCard.dayText(Calendar.current.startOfDay(for: .now)))
            DiaryCard(embedsTitle: false)
        case .hero:
            hero
            Rectangle().fill(Color.rule).frame(height: 1)
                .padding(.horizontal, 20)
        case .weekly:
            sectionHeader("이번 주 점검", trailing: weeklySubtitle)
            weeklyBar
            planReviewNudge
        case .attribution:
            attribution
        case .monthly:
            monthlyCard
        case .roadmap:
            roadmap
        case .lifeEvents:
            lifeEvents
        case .trajectory:
            trajectory
        case .diagnostics:
            diagnosticsStrip
            alerts
        case .members:
            memberBreakdown
        case .totals:
            totals
        }
    }

    private var completedAnchors: [Date] {
        sessions.filter(\.isComplete).map(\.weekAnchor)
    }

    private var streak: Int {
        ReviewWeek.streak(completedAnchors: completedAnchors, asOf: .now)
    }

    private var familyDidReviewThisWeek: Bool {
        completedAnchors.contains(ReviewWeek.anchor(for: .now))
    }

    /// **내가 적을 수 있는데 이번 주 아직 안 적힌 종목** (docs/09 4단계 정책).
    /// 넷이 각자 제 몫을 적으므로, 가족 기록이 있어도 내 몫이 남았으면 카드는
    /// 아직 "완료" 가 아니다. 남이 적어 준 것은 남은 것으로 세지 않는다.
    private var myPendingCount: Int {
        let anchor = ReviewWeek.anchor(for: .now)
        return holdings.filter {
            $0.isDue()
                && environment.mayEdit($0.account?.owner)
                && ($0.lastEnteredAt ?? .distantPast) < anchor
        }.count
    }

    private var didReviewThisWeek: Bool {
        familyDidReviewThisWeek && (!canEdit || myPendingCount == 0)
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
            sectionHeader("가족 총자산")
            Text(Won.abbreviated(rollup.netWorth, suffix: "원"))
                .font(.figure(38, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 20)
            if !rollup.liabilities.isZero {
                Text("자산 \(Won.abbreviated(rollup.assets)) · 부채 \(Won.abbreviated(rollup.liabilities))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)
                    .padding(.horizontal, 20)
            }
            // **계획선 위인가 아래인가** (docs/08-feedback.md 37번).
            // 총액만 보면 하락장에 앱을 열 이유가 없다. `계획보다 위` 라는
            // 사실은 총액이 줄어도 남는다 — 그 한 줄이 토요일마다 앱을 여는
            // 이유가 된다. 로드맵 M2 의 완료 기준이 이 줄이다.
            if let gap = planGap {
                Text(gap.text)
                    .font(.figure(12.5, weight: .medium))
                    .foregroundStyle(gap.isAhead ? Color.gain : Color.loss)
                    .padding(.top, 7)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
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

            // 끝낸 주에도 **다시 열 수 있다** (90번). 정책은 "뒤에 끝낸 사람이
            // 갱신" 이라 저장 쪽은 처음부터 재입력을 받았는데, 입구만 없었다.
            if canEdit {
                Button {
                    isReviewing = true
                } label: {
                    Text(didReviewThisWeek ? "다시 열기" : "지금 입력")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(didReviewThisWeek ? Color.muted : Color.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(didReviewThisWeek ? Color.ruleStrong : Color.ink, lineWidth: 1))
                }
            }
        }
        .padding(13)
        // 바탕이 `surface` 가 됐으므로 이 카드는 한 겹 위(`raised`)로 올린다.
        // 그러지 않으면 카드가 바탕에 묻혀 사라진다 (35번).
        .background(Color.raised)
        .padding(.horizontal, 20)
    }

    /// 소제목이 "이번 주 점검" 을 이미 말하므로 카드 안에는 상태만 (89번).
    private var weeklyTitle: String {
        if didReviewThisWeek { return "점검 완료" }
        if familyDidReviewThisWeek { return "내 몫 \(myPendingCount)건 남음" }
        // 적을 수 없는 사람에게 D-3 을 들이밀지 않는다. 재촉으로만 읽힌다.
        if !canEdit { return "기록 대기 중" }
        let days = ReviewWeek.daysUntilReview(from: .now)
        return days == 0 ? "오늘이 점검일입니다" : "토요일까지 D-\(days)"
    }

    private var weeklySubtitle: String {
        if streak == 0 {
            return canEdit ? "매주 토요일 오전에 알려드립니다" : "관리자가 매주 토요일에 적습니다"
        }
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

    // MARK: - 얼마 넣어서 얼마 자랐나 (docs/08-feedback.md 82번, C1)

    private struct AttributionRow: Identifiable {
        let id: String
        let label: String
        let split: ChangeAttribution?
    }

    /// **기록끼리 견준다.** 끝은 마지막 점검의 스냅샷, 시작은 그 창 앞의 마지막
    /// 스냅샷이다. 지금 값(종목 현재값)을 끝으로 쓰면 아직 안 적은 주에 "적립은
    /// 깔렸는데 증감은 0" 이 되어 수익이 가짜로 음수가 된다.
    private var attributionRows: [AttributionRow] {
        guard let plan, let latest = snapshots.last else { return [] }
        let calendar = Calendar.current
        let monthly = plan.effectiveMonthlyContribution(members: members)
        let end = Money(minorUnits: latest.netWorthMinor, currency: .krw)

        func row(_ label: String, before boundary: Date) -> AttributionRow {
            guard latest.weekAnchor >= boundary,
                  let base = snapshots.filter({ $0.weekAnchor < boundary }).max(by: { $0.weekAnchor < $1.weekAnchor })
            else { return AttributionRow(id: label, label: label, split: nil) }
            let days = calendar.dateComponents([.day], from: base.weekAnchor, to: latest.weekAnchor).day ?? 0
            let lumps = cashEvents
                .filter { $0.date > base.weekAnchor && $0.date <= latest.weekAnchor }
                .reduce(Money.zero(.krw)) { $0 + $1.amount }
            let split = ChangeAttribution.estimate(
                from: Money(minorUnits: base.netWorthMinor, currency: .krw), to: end,
                monthlyContribution: monthly, days: days, lumpSums: lumps)
            return AttributionRow(id: label, label: label, split: split)
        }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: latest.weekAnchor)) ?? latest.weekAnchor
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: latest.weekAnchor)) ?? latest.weekAnchor
        return [
            row("지난 점검", before: latest.weekAnchor),
            row("이번 달", before: monthStart),
            row("올해", before: yearStart),
        ]
    }

    @ViewBuilder
    private var attribution: some View {
        let rows = attributionRows
        if rows.contains(where: { $0.split != nil }), let latest = snapshots.last {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("얼마 넣어서 얼마 자랐나",
                              trailing: "마지막 점검 \(Self.shortDate.string(from: latest.weekAnchor)) 기준")
                // 세 숫자 칸은 폭을 고정하고 라벨이 나머지를 다 가진다 — `Grid` 는
                // 내용에 맞춰 줄어들어 화면 폭의 절반에서 끝났다.
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ForEach(["증감", "넣은 돈", "자란 돈"], id: \.self) { title in
                            Text(title)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.faint)
                                .frame(width: Self.attributionColumn, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 6)
                    Rectangle().fill(Color.rule).frame(height: 1)
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ink)
                            Spacer(minLength: 0)
                            if let split = row.split {
                                figure(split.change, tone: true)
                                figure(split.contributed, tone: false)
                                figure(split.gained, tone: true)
                            } else {
                                Text("기록 없음")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.faint)
                            }
                        }
                        .padding(.vertical, 9)
                        Rectangle().fill(Color.rule).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
                Text("넣은 돈은 계획의 월 적립을 날수로 나눠 어림한 값이고, 목돈 이벤트는 날짜대로 더했습니다. 자란 돈은 증감에서 그것을 뺀 나머지입니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.faint)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
    }

    private static let attributionColumn: CGFloat = 78

    private func figure(_ money: Money, tone: Bool) -> some View {
        Text(Won.compact(money, sign: .always))
            .font(.figure(12, weight: .medium))
            .foregroundStyle(tone ? (money.isNegative ? Color.loss : Color.gain) : Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Self.attributionColumn, alignment: .trailing)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    // MARK: - 지난달 회고 (docs/08-feedback.md 86번, C4)

    /// 지난달 요약 한 줄. 누르면 더보기의 회고 화면으로. 지난달 기록이 없으면 안 그린다.
    @ViewBuilder
    private var monthlyCard: some View {
        let period = Retrospective.Period.containing(.now, scope: .month, offset: -1)
        let summary = Retrospective.summarize(period: period, snapshots: snapshots, sessions: sessions,
                                              members: members, plan: plan, cashEvents: cashEvents,
                                              incomes: incomes, diary: diary, logs: logs)
        if summary.hasRecords {
            sectionHeader("지난달 회고", trailing: period.title)
            Button {
                AppRoute.shared.wantsRetrospective = true
                AppRoute.shared.selectedTab = RootView.Tab.more
            } label: {
                HStack(spacing: 10) {
                    Text(monthlyLine(summary))
                        .font(.figure(11.5))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.faint)
                }
                .padding(13)
                .background(Color.raised)
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
        }
    }

    private func monthlyLine(_ summary: Retrospective.Summary) -> String {
        var parts: [String] = []
        if let split = summary.attribution {
            parts.append("증감 \(Won.compact(split.change, sign: .always))")
            parts.append("넣은 \(Won.compact(split.contributed))")
            parts.append("자란 \(Won.compact(split.gained, sign: .always))")
        }
        parts.append("점검 \(summary.reviewedWeeks)/\(summary.weeksInPeriod)주")
        if summary.diaryDays > 0 { parts.append("일기 \(summary.diaryDays)일") }
        return parts.joined(separator: " · ")
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
    ///
    /// **순서는 연도다** (66번). 처음엔 의미의 순서(자산 2배 → 수익 > 적립금 →
    /// …)로 고정했는데, 타임라인에서 2034 다음에 2028 이 오면 틀린 그림으로
    /// 읽힌다. `지금` 이 맨 앞, 오는 것은 연도순, 은퇴 뒤에 오는 것은 은퇴 뒤에,
    /// 오지 않는 것은 맨 뒤에 `—` 로.
    private var roadmapStops: [RoadmapStrip.Stop] {
        guard let plan, let projection else { return [] }
        let thisYear = Calendar.current.component(.year, from: .now)

        var stops: [RoadmapStrip.Stop] = [
            .init(year: thisYear, amount: rollup.netWorth, label: "지금", isNow: true, isGoal: false)
        ]

        var coming: [RoadmapStrip.Stop] = []
        var never: [RoadmapStrip.Stop] = []
        for kind in [MilestoneKind.doubled, .returnsExceedContribution,
                     .returnsExceedSalary, .targetReached] {
            if let hit = projection.milestone(kind) {
                coming.append(.init(year: hit.year, amount: hit.balance,
                                    label: kind.label, isNow: false, isGoal: false,
                                    state: hit.year <= thisYear ? .passed : .ahead))
            } else {
                never.append(.init(year: nil, amount: nil, label: kind.label,
                                   isNow: false, isGoal: false, state: .never))
            }
        }

        // 은퇴 정거장은 **은퇴 시점**이다. 인출 구간까지 그리기 시작하면서
        // years.last 가 은퇴 후 30년 뒤가 됐다 — 거기에 "은퇴" 라벨을 붙이면 틀린다.
        if let atRetirement = projection.years.last(where: { $0.year <= plan.retirementYear }) {
            coming.append(.init(year: atRetirement.year, amount: atRetirement.endBalance,
                                label: "은퇴", isNow: false, isGoal: true))
        }

        // 같은 해면 은퇴가 뒤 — 그 해 안에서 이룬 것을 은퇴 앞에 둔다.
        let ordered = coming.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            if l.year != r.year { return (l.year ?? .max) < (r.year ?? .max) }
            if l.isGoal != r.isGoal { return !l.isGoal }
            return lhs.offset < rhs.offset
        }.map(\.element)

        stops += ordered
        stops += never
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
                RoadmapStrip(stops: roadmapStops) { selectedStop = $0 }
                    .padding(.bottom, 4)
                Text("정거장을 누르면 그때까지의 적립 · 수익과 구성원별 예상이 보입니다")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 궤적

    private var plan: Plan? { plans.first }

    private var projection: ProjectionResult? {
        plan?.projection(from: rollup.netWorth, cashEvents: cashEvents, incomes: incomes, members: members)
    }

    /// **1년에 한 번은 가정을 다시 본다** (docs/08-feedback.md 43번).
    ///
    /// 주간 점검은 숫자를 적는 일이고, 기대수익률·물가·목표 금액은 그대로
    /// 20년을 간다. 계획을 마지막으로 고친 지 1년이 넘으면 여기서 한 번 부른다.
    @ViewBuilder
    private var planReviewNudge: some View {
        if let years = PlanTrack.yearsSincePlanReview(plan) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("계획을 \(years)년째 안 고쳤습니다")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text("기대수익률 · 물가 · 목표 금액을 지금도 그렇게 보시나요?")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Button("계획 열기") { AppRoute.shared.selectedTab = RootView.Tab.plan }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
            .padding(13)
            .background(Color.raised)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    // MARK: - 계획선 (docs/08-feedback.md 37·46번)

    /// 계산은 `PlanTrack` 이 한다. **현황판 · 점검 완료 화면 · 1페이지가 같은
    /// 함수를 쓴다** — 37번에서 여기에만 붙였다가 나머지 둘을 빠뜨렸다.
    private var planProjection: ProjectionResult? {
        PlanTrack.projection(plan: plan, snapshots: snapshots, cashEvents: cashEvents,
                             incomes: incomes, members: members)
    }

    private var planGap: PlanTrack.Gap? {
        PlanTrack.gap(planProjection, actual: rollup.netWorth)
    }

    /// 계획선이 그려질 수 있나. 범례가 이걸 보고 줄을 넣는다.
    private var hasPlanLine: Bool {
        PlanTrack.anchor(plan: plan, snapshots: snapshots) != nil
    }

    /// 과거는 매주 적어 넣은 스냅샷, 미래는 예측. 같은 축에 잇는다.
    private var trajectoryPoints: [TrajectoryChart.Point] {
        var result = snapshots.map {
            TrajectoryChart.Point(date: $0.weekAnchor, minor: $0.netWorthMinor, series: .actual)
        }
        // 예측선은 오늘에서 출발한다. 과거 마지막 점과 이어 붙어 끊겨 보이지 않는다.
        //
        // **지평선까지 다 만든다** (docs/08-feedback.md 36번). 자르는 것은
        // 차트의 기간 선택이 한다 — 여기서 미리 잘라 버리면 `전체` 를 골라도
        // 은퇴 이후에 자산이 줄어드는 구간을 볼 수 없다.
        if let projection {
            let monthly = projection.points.enumerated()
                .filter { $0.offset % 3 == 0 || $0.offset == projection.points.count - 1 }
                .map { TrajectoryChart.Point(date: $0.element.date,
                                             minor: $0.element.nominal.minorUnits,
                                             realMinor: $0.element.real.minorUnits,
                                             series: .projected) }
            result.append(contentsOf: monthly)
        }

        // 계획선. 과거 구간까지 이어지므로 여기서만 "위인지 아래인지" 가 보인다.
        if let planProjection {
            let line = planProjection.points.enumerated()
                .filter { $0.offset % 3 == 0 || $0.offset == planProjection.points.count - 1 }
                .map { TrajectoryChart.Point(date: $0.element.date,
                                             minor: $0.element.nominal.minorUnits,
                                             realMinor: $0.element.real.minorUnits,
                                             series: .plan) }
            result.append(contentsOf: line)
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
                retirementDate: plan.map {
                    Plan.endDate(retirementYear: $0.retirementYear,
                                 notBefore: Calendar.current.startOfDay(for: .now))
                },
                events: milestoneMarks
            )
            .padding(.horizontal, 16)

            HStack(spacing: 14) {
                legend(color: .ink, dashed: false, label: "실제 기록")
                legend(color: .dad, dashed: true, label: "예측")
                if hasPlanLine {
                    legend(color: .muted, dashed: true, label: "계획선")
                }
                if chartSpan == .retirement || chartSpan == .all,
                   let target = plan?.targetAmount, !target.isZero {
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
        // 적립액은 계획이 실제로 굴리는 값으로 본다 — 구성원별로 나눠 넣는
        // 집은 계획의 한 덩어리 칸이 0 이라 이 줄이 통째로 사라졌다 (51번).
        guard let plan, plan.effectiveMonthlyContribution(members: members).minorUnits > 0,
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
        return "연 \(PercentFormatter.oneDecimal(plan.annualReturn.fraction))% · 은퇴 후 \(PercentFormatter.oneDecimal(plan.postRetirementReturn.fraction))% · 물가 \(PercentFormatter.oneDecimal(plan.inflation.fraction))% 가정 · 입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다"
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
                        // **사람마다 연속 주** (C8). 안정화 기준 2 "넷이 각자
                        // 4주 연속" 을 앱이 직접 센다.
                        Text(memberStreakText(member))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.faint)
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

    /// "3주 연속 · 이번 주 적음" 같은 한 줄. 아직 한 번도 안 적은 사람은
    /// 재촉하지 않는다 — 빈 줄 대신 "기록 없음".
    private func memberStreakText(_ member: Member) -> String {
        let streak = ReviewSession.memberStreak(member.id, sessions: sessions)
        let thisWeek = ReviewSession.enteredThisWeek(member.id, sessions: sessions)
        if streak == 0 { return thisWeek ? "이번 주 적음" : "기록 없음" }
        return "\(streak)주 연속" + (thisWeek ? " · 이번 주 적음" : "")
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
