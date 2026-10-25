import Charts
import Core
import Foundation
import SwiftUI

/// 순자산 궤적 — 이 앱이 존재하는 이유.
///
/// 왼쪽은 매주 직접 적어 넣은 **사실**, 오른쪽은 가정에 따른 **추정**이다.
/// 둘을 같은 축 위에 잇되 실선과 점선으로 절대 섞이지 않게 그린다 (설계 2.2.3).
///
/// **Y축은 선형이고 0에서 시작한다** (docs/08-feedback.md 31번).
/// 한때 로그였는데, 그 축은 일정 비율 성장을 **직선으로 펴 버린다** —
/// `느린 부자` 라는 이름 그대로 느림이 쌓여 휘는 순간을 보려고 만든
/// 그래프가 정작 그 휘어짐을 지우고 있었다.
///
/// 선형의 값은 대신 **앞 10년이 바닥에 눌리는 것**이다. 은퇴까지 63억을
/// 168pt 에 담으면 지금의 3억은 바닥에서 8pt 고, 한 주에 500만원이 움직여도
/// 0.13pt 라 눈에 보이지 않는다. 그래서 축을 바꾸는 대신 **보는 창을 좁힌다** —
/// `1년` · `5년` 은 범위가 작아 선형에서도 주간 증감이 또렷하다.
/// 축은 하나(선형)로 두므로 "지금 어떤 눈금인가" 를 사람이 신경 쓸 필요가 없다.
///
/// 기간은 현황판과 구성원 궤적이 **같은 값을 나눠 쓴다**. 두 화면에서 다른
/// 기간을 보면 같은 자산을 두 번 다르게 읽게 된다.
struct TrajectoryChart: View {

    struct Point: Identifiable, Hashable {
        enum Series: String {
            case actual = "실제 기록"
            case projected = "예측"
            /// **계획을 세운 날에서 출발한 선** (docs/08-feedback.md 37번).
            /// 이것이 있어야 "이번 주 숫자가 계획선 위인지 아래인지" 를 볼 수 있다 —
            /// 로드맵 M2 의 완료 기준인데 여태 비어 있었다.
            case plan = "계획선"
        }
        let date: Date
        let minor: Int
        /// 오늘 돈으로 환산한 값 (docs/08-feedback.md 47번).
        /// 없으면 명목과 같다 — 과거 기록은 이미 그때의 돈이라 환산할 것이 없다.
        var realMinor: Int?
        let series: Series

        var id: String { "\(series.rawValue)-\(date.timeIntervalSince1970)" }
        func value(real: Bool) -> Double { Double(real ? (realMinor ?? minor) : minor) }
    }

    /// 인생 이벤트. 로드맵의 뼈대를 흔들지 않으면서 "그 사건이 궤적의 어디쯤
    /// 오는가" 를 보여주는 자리다 (docs/08-feedback.md 5번).
    struct EventMark: Identifiable, Hashable {
        let date: Date
        let label: String
        var id: String { "\(label)-\(date.timeIntervalSince1970)" }
    }

    /// 보는 창.
    ///
    /// `1년` · `5년` 은 **오늘을 가운데 두고 앞뒤로** 자른다. 앞뒤 둘 다 자르는
    /// 이유는 기록이 쌓이기 때문이다 — 미래만 자르면 20년 뒤에는 지난 20년치가
    /// 창에 남아 `1년` 이 다시 넓은 창이 된다.
    ///
    /// `은퇴까지` 는 은퇴 시점에서 끊고, `전체` 는 계획의 지평선까지 — **은퇴
    /// 이후 인출 구간을 포함해** 그린다 (docs/08-feedback.md 36번).
    /// 자산이 줄어드는 구간을 봐야 노후 계획이 완성되기 때문이다.
    enum Span: String, CaseIterable, Identifiable {
        case year1 = "1년"
        case year5 = "5년"
        case retirement = "은퇴까지"
        case all = "전체"

        var id: String { rawValue }

        /// 오늘 앞뒤로 볼 햇수. 나머지 둘은 날짜로 자른다.
        var years: Int? {
            switch self {
            case .year1: return 1
            case .year5: return 5
            case .retirement, .all: return nil
            }
        }
    }

    /// 계열마다 색과 선 모양. 범례가 같은 값을 읽어야 그림과 설명이 어긋나지 않는다.
    static func color(of series: Point.Series) -> Color {
        switch series {
        case .actual: return .ink
        case .projected: return .dad
        case .plan: return .muted
        }
    }

    static func stroke(of series: Point.Series) -> StrokeStyle {
        switch series {
        case .actual: return StrokeStyle(lineWidth: 2.2, lineCap: .round)
        case .projected: return StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 3])
        // 계획선은 가장 조용하다. 비교 기준이지 주인공이 아니다.
        case .plan: return StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1, 3])
        }
    }

    /// 현황판과 구성원 궤적이 함께 읽는다. 화면 밖(범례·목표선)에서도 이 값을
    /// 봐야 해서 열쇠를 공개해 둔다.
    static let spanKey = "trajectory.span"
    /// **실질(오늘 돈) 로 볼 것인가** (로드맵 M2 · docs/08-feedback.md 47번).
    ///
    /// 30년 뒤 63억이 지금 얼마인지가 노후 준비의 진짜 질문이다. 화면마다
    /// `오늘 돈으로 …` 를 덧붙여 적고 있었지만 **궤적 자체를 실질로 보는**
    /// 선택지는 없었다.
    static let realKey = "trajectory.real"

    let points: [Point]
    let today: Date
    let targetMinor: Int
    /// 은퇴 시점. `은퇴까지` 창이 여기서 끊는다. 없으면 자르지 않는다.
    var retirementDate: Date? = nil
    var events: [EventMark] = []
    /// 크게 보기 창의 제목 (204번). 현황판은 `순자산 궤적`, 구성원 화면은 `○○ 궤적`.
    var title = "순자산 궤적"
    /// **크게 보기 창 안에서 그리나** (204번). 차트가 남은 높이를 다 쓰고, 눈금 · 점 · 읽은 값 글씨가
    /// 커지고, 손을 떼도 마지막에 짚은 시점의 값이 남는다. 창을 여는 돋보기는 숨는다.
    var isLarge = false
    /// **은퇴 해의 목표를 그해 돈으로** (208번). 목표(`targetMinor`)는 오늘 돈이다(194번 E3). 오늘 돈 보기에서는
    /// 목표 그대로 가로선을 긋고, 명목 보기에서는 은퇴 시점에 이 값으로 점 하나를 찍는다. 예전에는 명목 축에
    /// 오늘 돈 목표를 가로선으로 그어 목표가 실제보다 낮아 보였고, 오늘 돈 보기에서는 목표가 사라졌다.
    var targetAtRetirementMinor: Int? = nil
    /// 자산이 바닥나는 때 — 있으면 크게 보기에 세로선으로 (208번).
    var depletionDate: Date? = nil
    /// 크게 보기 차트 아래의 숫자 표 (208번). 카드에서는 그리지 않고 창에 건네기만 한다.
    var facts: [Fact] = []

    /// 크게 보기 아래 표의 한 줄 (208번).
    struct Fact: Hashable {
        let label: String
        let value: String
    }

    /// 크게 보기 창에 건네는 것 (204번). 열 때의 값을 그대로 담는다 — 창은 `RootView` 가
    /// **탭 바깥에서** 띄운다(199번 C4: 아이패드를 돌리면 탭 안의 창이 닫혔다). 기간 · 오늘 돈
    /// 보기는 `@AppStorage` 라 카드와 창이 같은 값을 나눠 쓴다.
    struct Expanded: Identifiable {
        let id = UUID()
        let title: String
        let points: [Point]
        let today: Date
        let targetMinor: Int
        let retirementDate: Date?
        let events: [EventMark]
        var targetAtRetirementMinor: Int? = nil
        var depletionDate: Date? = nil
        var facts: [Fact] = []
    }

    /// 기본은 `은퇴까지` — 이 앱이 답하는 질문의 기본 범위다.
    /// 저장된 값이 있으면 그것을 따른다.
    @AppStorage(TrajectoryChart.spanKey) private var span: Span = .retirement
    @AppStorage(TrajectoryChart.realKey) private var showsReal = false
    /// **누른 시점** (docs/08-feedback.md 84번, C2). 차트가 예쁘지만 숫자를
    /// 읽을 수 없었다 — 누르거나 끌면 그 시점의 실제·예측·계획선 값을 적는다.
    @State private var scrubDate: Date?
    /// 크게 보기에서 **손을 뗀 뒤에도 남기는** 시점 (204번). 카드에서는 손을 떼면 사라진다 —
    /// 좁은 카드에 값이 계속 남으면 다음에 열었을 때 무슨 값인지 헷갈린다.
    @State private var pinnedDate: Date?

    /// 지금 짚은 시점 — 누르는 중이면 그 자리, 크게 보기에서는 마지막에 짚은 자리.
    private var markedDate: Date? { scrubDate ?? (isLarge ? pinnedDate : nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("기간", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: isLarge ? 360 : 260)
                Spacer(minLength: 0)
                if !isLarge {
                    expandButton
                }
            }

            // **폭을 묶지 않는다.** 위 세그먼트 컨트롤을 따라 260 으로 잘라 뒀더니
            // 스위치가 카드 한가운데 떠서 고장처럼 보였다. 스위치는 차트·범례의
            // 오른쪽 끝과 맞아야 한 덩어리로 읽힌다.
            Toggle(isOn: $showsReal) {
                Text("오늘 돈으로 보기")
                    .font(.scaled(11.5))
                    .foregroundStyle(Color.muted)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if visiblePoints.count < 2 {
                placeholder
            } else {
                chart
                readoutLine
            }
        }
        .onChange(of: scrubDate) { _, date in
            if let date { pinnedDate = date }
        }
        // 기간을 바꾸면 짚어 둔 시점이 창 밖일 수 있다 — 지운다.
        .onChange(of: span) { _, _ in pinnedDate = nil }
    }

    /// **돋보기** (204번, 10-22 사용자: *"순자산궤적에 돋보기 같은 버튼을 하나 만들어서 크게 자세히 볼 수 있는
    /// 기능"*). 카드의 차트는 168pt 라 은퇴까지를 보면 지금의 몇 년이 바닥에 눌리고 눈금 글씨가 8pt 다.
    /// 누르는 자리는 44pt 너비로.
    private var expandButton: some View {
        Button {
            AppRoute.shared.expandedTrajectory = Expanded(
                title: title, points: points, today: today, targetMinor: targetMinor,
                retirementDate: retirementDate, events: events,
                targetAtRetirementMinor: targetAtRetirementMinor, depletionDate: depletionDate, facts: facts)
        } label: {
            Image(systemName: "plus.magnifyingglass")
                .font(.scaled(16, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 크게 보기")
    }

    /// 차트 아래 한 줄. 누르기 전에는 누르라고 알려 준다.
    @ViewBuilder
    private var readoutLine: some View {
        if let markedDate, let readout = readout(at: markedDate) {
            Text(readout)
                .font(.figure(isLarge ? 13 : 10.5, weight: .medium))
                .foregroundStyle(Color.dad)
                .lineLimit(2)
        } else {
            Text(isLarge ? "차트를 누르거나 끌면 그 시점의 값이 보이고, 손을 떼도 남습니다"
                         : "차트를 누르거나 끌면 그 시점의 값이 보입니다")
                .font(.scaled(isLarge ? 11.5 : 9.5))
                .foregroundStyle(Color.faint)
        }
    }

    /// 누른 날짜에 가장 가까운 점을 계열마다 하나씩 찾아 한 줄로 적는다.
    /// 실제 기록은 주마다 있으니 60일 안, 예측·계획선은 분기 점이라 200일 안에서만.
    private func readout(at date: Date) -> String? {
        let calendar = Calendar.app
        var parts: [String] = []
        var shownDate: Date?
        for series in [Point.Series.actual, .projected, .plan] {
            let candidates = visiblePoints.filter { $0.series == series }
            guard let nearest = candidates.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }) else { continue }
            let days = abs(calendar.dateComponents([.day], from: nearest.date, to: date).day ?? 0)
            guard days <= (series == .actual ? 60 : 200) else { continue }
            if shownDate == nil { shownDate = nearest.date }
            let money = Money(minorUnits: Int(nearest.value(real: showsReal)), currency: .krw)
            parts.append("\(series.rawValue) \(Won.compact(money))")
        }
        guard let shownDate, !parts.isEmpty else { return nil }
        let year = calendar.component(.year, from: shownDate)
        let month = calendar.component(.month, from: shownDate)
        return "\(year).\(String(format: "%02d", month)) · " + parts.joined(separator: " · ")
    }

    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                LineMark(
                    x: .value("시점", point.date),
                    y: .value("순자산", point.value(real: showsReal)),
                    series: .value("구분", point.series.rawValue)
                )
                .foregroundStyle(Self.color(of: point.series))
                .lineStyle(Self.stroke(of: point.series))

                // 은퇴까지를 보면 과거 몇 달은 전체 폭의 1%도 안 되어 선이 사라진다.
                // 점을 함께 찍어야 "실제로 적어 온 기록"이 눈에 남는다.
                if point.series == .actual {
                    PointMark(
                        x: .value("시점", point.date),
                        y: .value("순자산", point.value(real: showsReal))
                    )
                    .foregroundStyle(Color.ink)
                    .symbolSize(isLarge ? 34 : 20)
                }
            }

            // **목표** (208번). 목표는 오늘 돈이라(194번 E3) 오늘 돈 보기에서는 그 값에 가로선을, 명목 보기에서는
            // 은퇴 시점에 그해 돈으로 점 하나를 찍는다. 카드는 글씨 없이(범례가 이름을 단다), 크게 보기는 값까지.
            // 글씨는 그림 안쪽에 맞춘다(`.fit(to: .plot)`) — 가장자리에서 잘리던 까닭.
            if showsTarget && showsReal {
                RuleMark(y: .value("목표", Double(targetMinor)))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        if isLarge {
                            markLabel("목표 \(money(Double(targetMinor))) · 오늘 돈", color: .ink)
                        }
                    }
            }
            if let target = nominalTarget {
                PointMark(x: .value("시점", target.date), y: .value("목표", target.value))
                    .symbol(.diamond)
                    .symbolSize(isLarge ? 90 : 46)
                    .foregroundStyle(Color.ink.opacity(0.7))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        if isLarge {
                            markLabel("목표 \(money(target.value))\n오늘 돈 \(money(Double(targetMinor)))", color: .ink)
                        }
                    }
            }

            // **크게 보기의 이정표** (208번) — 지금 · 은퇴 · 목표에 닿는 해 · 고갈. 카드는 그대로 둔다(좁아서 겹친다).
            if isLarge {
                if let now = latestActual {
                    PointMark(x: .value("시점", now.date), y: .value("순자산", now.value(real: showsReal)))
                        .symbolSize(70)
                        .foregroundStyle(Color.ink)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                            markLabel("지금 \(money(now.value(real: showsReal)))", color: .ink)
                        }
                }
                if let retirementDate, inWindow(retirementDate) {
                    RuleMark(x: .value("은퇴", retirementDate))
                        .foregroundStyle(Color.dad.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                            markLabel("은퇴 \(year(retirementDate))", color: .dad)
                        }
                    if let peak = projectedPoint(near: retirementDate) {
                        PointMark(x: .value("시점", peak.date), y: .value("순자산", peak.value(real: showsReal)))
                            .symbolSize(60)
                            .foregroundStyle(Color.dad)
                            .annotation(position: .top, alignment: .center, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                                markLabel(money(peak.value(real: showsReal)), color: .dad)
                            }
                    }
                }
                if let reach = targetReached, inWindow(reach.date) {
                    PointMark(x: .value("시점", reach.date), y: .value("순자산", reach.value(real: showsReal)))
                        .symbolSize(60)
                        .foregroundStyle(Color.gain)
                        .annotation(position: .bottom, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                            markLabel("목표 닿음 \(year(reach.date))", color: .gain)
                        }
                }
                if let depletionDate, inWindow(depletionDate) {
                    RuleMark(x: .value("고갈", depletionDate))
                        .foregroundStyle(Color.loss.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .annotation(position: .trailing, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                            markLabel("고갈 \(year(depletionDate))", color: .loss)
                        }
                }
            }

            // 인생 이벤트는 x축에 눈금으로 선다. 개수가 늘어도 눈금이 촘촘해질
            // 뿐, 로드맵의 여섯 칸은 그대로다.
            ForEach(visibleEvents) { event in
                RuleMark(x: .value("이벤트", event.date))
                    .foregroundStyle(Color.muted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    // 크게 보기는 그림 안쪽 아래에 세운다 — 바깥(아래)에 두면 잘라 낸 그림 밖이라 안 보였다 (208번).
                    .annotation(position: isLarge ? .trailing : .bottom,
                                alignment: isLarge ? .bottom : .center, spacing: isLarge ? 3 : 1,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        Text(event.label)
                            .font(.scaled(isLarge ? 10 : 7.5))
                            .foregroundStyle(isLarge ? Color.muted : Color.faint)
                            .lineLimit(1)
                    }
            }

            RuleMark(x: .value("오늘", today))
                .foregroundStyle(Color.ink)
                .lineStyle(StrokeStyle(lineWidth: 1))

            // 누른 자리 (84번).
            if let markedDate {
                RuleMark(x: .value("선택", markedDate))
                    .foregroundStyle(Color.dad.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .chartXSelection(value: $scrubDate)
        .chartYScale(domain: domain)
        // 궤적을 벗어난 선이 아래 카드 위에 그려지지 않게 한다.
        .chartPlotStyle { plot in plot.clipped() }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: isLarge ? 6 : 4)) { value in
                AxisGridLine().foregroundStyle(Color.rule)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        // 금액 가리기를 켜면 축 눈금도 함께 가려진다.
                        // 예전 눈금은 자체 포맷터를 써서 이것만 새어 나갔다.
                        Text(axisLabel(raw))
                            .font(.figure(isLarge ? 10 : 8))
                            .foregroundStyle(Color.faint)
                    }
                }
            }
        }
        .chartXAxis {
            // **처음 해와 끝 해를 늘 적는다** (208번). 예전에는 해마다 몇 칸씩 건너뛴 눈금만 있어 시작 해가
            // 안 보였고, 끝 눈금이 그림 오른쪽 끝에 붙으면 글씨가 반쯤 잘렸다("20…"). 양 끝 글씨는 안쪽으로 붙인다.
            AxisMarks(values: xTicks) { value in
                AxisGridLine().foregroundStyle(Color.rule.opacity(0.6))
                // 한국어 로케일에서 .dateTime.year() 는 "2031년" 이 된다.
                // 축 라벨은 8pt 라서 그 한 글자가 눈금끼리 부딪히게 만든다.
                AxisValueLabel(anchor: value.index == 0 ? .topLeading
                                       : (value.index == value.count - 1 ? .topTrailing : .top)) {
                    if let date = value.as(Date.self) {
                        Text(verbatim: "\(Calendar.app.component(.year, from: date))")
                            .font(.figure(isLarge ? 10 : 8))
                            .foregroundStyle(Color.faint)
                    }
                }
            }
        }
        // 크게 보기는 남은 높이를 다 쓴다 (204번).
        .frame(minHeight: isLarge ? 240 : 168, maxHeight: isLarge ? .infinity : 168)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Text("궤적은 점검을 두 번 하면 그려집니다")
                .font(.scaled(12))
                .foregroundStyle(Color.muted)
            Text("계획 탭에서 월 적립액과 기대수익률을 넣으면 예측선이 먼저 나타납니다")
                .font(.scaled(10))
                .foregroundStyle(Color.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
    }

    // MARK: - 보는 창

    /// 창 안에 드는 점만 그린다.
    private var visiblePoints: [Point] {
        guard let range = dateRange else { return points }
        return points.filter { range.contains($0.date) }
    }

    private var visibleEvents: [EventMark] {
        guard let range = dateRange else { return events }
        return events.filter { range.contains($0.date) }
    }

    private var dateRange: ClosedRange<Date>? {
        // 은퇴까지는 오른쪽만 자른다. 왼쪽(적어 온 기록)은 남길수록 좋다.
        if span == .retirement {
            guard let retirementDate else { return nil }
            let first = points.map(\.date).min() ?? today
            return min(first, today)...max(retirementDate, today)
        }
        guard let years = span.years else { return nil }
        let calendar = Calendar.app
        guard
            let from = calendar.date(byAdding: .year, value: -years, to: today),
            let to = calendar.date(byAdding: .year, value: years, to: today)
        else { return nil }
        return from...to
    }

    /// **목표선은 넓은 창에서만 그린다.** 좁은 창에서 수십억짜리 선을 그리면
    /// 그 하나 때문에 축이 늘어나 나머지가 전부 바닥에 눌린다.
    private var showsTarget: Bool {
        (span == .retirement || span == .all) && targetMinor > 0
    }

    /// 명목 보기의 목표 점 — 은퇴 시점 · 그해 돈 (208번).
    private var nominalTarget: (date: Date, value: Double)? {
        guard showsTarget, !showsReal, let retirementDate, inWindow(retirementDate),
              let nominal = targetAtRetirementMinor, nominal > 0 else { return nil }
        return (retirementDate, Double(nominal))
    }

    /// 창 안의 날짜인가 — 실제 · 예측 점이 그리는 범위.
    private func inWindow(_ date: Date) -> Bool {
        guard let first = visiblePoints.map(\.date).min(), let last = visiblePoints.map(\.date).max()
        else { return false }
        return date >= first && date <= last
    }

    /// 가장 최근에 적은 기록.
    private var latestActual: Point? {
        visiblePoints.filter { $0.series == .actual }.max { $0.date < $1.date }
    }

    /// 그 날짜에 가장 가까운 예측 점(200일 안).
    private func projectedPoint(near date: Date) -> Point? {
        let candidates = visiblePoints.filter { $0.series == .projected }
        guard let nearest = candidates.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= 200 * 86_400 else { return nil }
        return nearest
    }

    /// 예측이 **오늘 돈으로** 목표에 처음 닿는 점 (목표가 오늘 돈이라 같은 돈끼리 견준다, 194번 E3).
    private var targetReached: Point? {
        guard targetMinor > 0 else { return nil }
        return points
            .filter { $0.series == .projected && $0.date > today }
            .sorted { $0.date < $1.date }
            .first { ($0.realMinor ?? $0.minor) >= targetMinor }
    }

    private func year(_ date: Date) -> String {
        String(Calendar.app.component(.year, from: date))
    }

    private func money(_ raw: Double) -> String {
        Won.compact(Money(minorUnits: SafeMath.clampedInt(raw), currency: .krw))
    }

    /// 그림 위 글씨 하나 — 바탕을 깔아 선 위에서도 읽힌다.
    private func markLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.figure(10, weight: .semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.raised.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - 축

    /// **바닥은 0이다.** 최솟값에서 시작하면 없는 기울기가 생겨 증감이 실제보다
    /// 커 보인다. 복리를 정직하게 보여주려면 바닥이 0이어야 한다.
    /// 순자산이 음수인 구간이 있으면 그때만 0 아래로 내린다.
    private var domain: ClosedRange<Double> {
        let values = visiblePoints.map { $0.value(real: showsReal) }
        var upper = values.max() ?? 0
        if showsTarget && showsReal { upper = max(upper, Double(targetMinor)) }
        if let target = nominalTarget { upper = max(upper, target.value) }
        let lower = min(0, values.min() ?? 0)
        // 위쪽에 숨 쉴 틈을 둔다. 최고점이 천장에 닿으면 선이 잘려 보인다.
        return lower...max(upper * 1.08, lower + 1_000_000)
    }

    /// 축 눈금 글자. 눈금은 대개 딱 떨어지는 값이라 `60.0억` 이 아니라 `60억` 이다.
    /// 소수가 필요할 때만 한 자리를 붙인다.
    private func axisLabel(_ raw: Double) -> String {
        // **여기서 앱이 죽었다** (159번, 2026-09-19). `raw` 는 우리가 만든 값이
        // 아니라 Charts 가 도메인에서 뽑아 건네주는 것이라, 자료에 터무니없이
        // 큰 금액이 하나 들어가면 `Int` 범위를 넘는다. `Int(raw)` 는 그때
        // 그 자리에서 트랩이고, 현황판이 첫 화면이라 **값을 고칠 기회조차
        // 없었다.** 이상한 자료는 이상한 눈금으로 보여 줘야지 멈추면 안 된다.
        let value = SafeMath.clampedInt(raw)
        let eok = 100_000_000
        guard value >= eok else {
            return Won.compact(Money(minorUnits: value, currency: .krw))
        }
        // **나누기를 먼저.** `value * 10` 도 같은 이유로 넘친다.
        // (value + 0.5억) / 0.1억 은 value/1억 을 소수 첫째 자리에서 반올림한 것과 같다.
        let tenths = (value + eok / 20) / (eok / 10)
        let text = tenths % 10 == 0 ? "\(tenths / 10)억" : "\(tenths / 10).\(tenths % 10)억"
        return AmountPrivacy.mask(text)
    }

    /// **x 눈금** (208번) — 첫 점 · 끝 점의 해와, 그 사이 `xStride` 해마다 딱 떨어지는 해(2030 · 2040 …).
    /// 양 끝 해와 같은 해이거나 반 칸보다 가까운 안쪽 눈금은 뺀다 — 글씨가 겹친다.
    private var xTicks: [Date] {
        let dates = visiblePoints.map(\.date)
        guard let first = dates.min(), let last = dates.max(), first < last else { return [] }
        let calendar = Calendar.app
        let firstYear = calendar.component(.year, from: first)
        let lastYear = calendar.component(.year, from: last)
        let step = max(1, xStride)
        let minGap = Double(step) * 365.25 * 86_400 / 2
        var ticks = [first]
        var year = (firstYear / step + 1) * step
        while year < lastYear {
            if let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
               date > first,
               date.timeIntervalSince(first) >= minGap,
               last.timeIntervalSince(date) >= minGap {
                ticks.append(date)
            }
            year += step
        }
        if lastYear != firstYear { ticks.append(last) }
        return ticks
    }

    /// 기간이 길면 눈금을 성기게 둔다.
    private var xStride: Int {
        guard let first = visiblePoints.first?.date, let last = visiblePoints.last?.date
        else { return 5 }
        let years = Calendar.app.dateComponents([.year], from: first, to: last).year ?? 0
        switch years {
        case ..<3: return 1
        case ..<8: return 2
        // 은퇴까지는 보통 20~30년이다. 여기서 10년 간격이 되면 눈금이 둘밖에
        // 안 남아 어느 해쯤인지 읽히지 않는다.
        case ..<32: return 5
        default: return 10
        }
    }
}
