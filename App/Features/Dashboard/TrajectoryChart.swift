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
/// `느린 부자의 기록` 이라는 이름 그대로 느림이 쌓여 휘는 순간을 보려고 만든
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

    /// 기본은 `은퇴까지` — 이 앱이 답하는 질문의 기본 범위다.
    /// 저장된 값이 있으면 그것을 따른다.
    @AppStorage(TrajectoryChart.spanKey) private var span: Span = .retirement
    @AppStorage(TrajectoryChart.realKey) private var showsReal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("기간", selection: $span) {
                ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Toggle(isOn: $showsReal) {
                Text("오늘 돈으로 보기")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(maxWidth: 260)

            if visiblePoints.count < 2 {
                placeholder
            } else {
                chart
            }
        }
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
                    .symbolSize(20)
                }
            }

            // 목표선에는 주석을 달지 않는다. 차트 주석은 leading 이든 trailing 이든
            // 가장자리에서 잘린다. 라벨은 범례 줄에 둔다.
            if showsTarget {
                // 목표는 **명목으로 적은 값**이다. 실질 축에서 그대로 그으면
                // 선만 위로 뜬다. 그래서 실질 보기에서는 목표선을 접는다.
                RuleMark(y: .value("목표", Double(targetMinor)))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            }

            // 인생 이벤트는 x축에 눈금으로 선다. 개수가 늘어도 눈금이 촘촘해질
            // 뿐, 로드맵의 여섯 칸은 그대로다.
            ForEach(visibleEvents) { event in
                RuleMark(x: .value("이벤트", event.date))
                    .foregroundStyle(Color.muted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .bottom, alignment: .center, spacing: 1) {
                        Text(event.label)
                            .font(.system(size: 7.5))
                            .foregroundStyle(Color.faint)
                            .lineLimit(1)
                    }
            }

            RuleMark(x: .value("오늘", today))
                .foregroundStyle(Color.ink)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: domain)
        // 궤적을 벗어난 선이 아래 카드 위에 그려지지 않게 한다.
        .chartPlotStyle { plot in plot.clipped() }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.rule)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        // 금액 가리기를 켜면 축 눈금도 함께 가려진다.
                        // 예전 눈금은 자체 포맷터를 써서 이것만 새어 나갔다.
                        Text(axisLabel(raw))
                            .font(.figure(8))
                            .foregroundStyle(Color.faint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .year, count: xStride)) { value in
                AxisGridLine().foregroundStyle(Color.rule.opacity(0.6))
                // 한국어 로케일에서 .dateTime.year() 는 "2031년" 이 된다.
                // 축 라벨은 8pt 라서 그 한 글자가 눈금끼리 부딪히게 만든다.
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(verbatim: "\(Calendar.current.component(.year, from: date))")
                            .font(.figure(8))
                            .foregroundStyle(Color.faint)
                    }
                }
            }
        }
        .frame(height: 168)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Text("궤적은 점검을 두 번 하면 그려집니다")
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
            Text("계획 탭에서 월 적립액과 기대수익률을 넣으면 예측선이 먼저 나타납니다")
                .font(.system(size: 10))
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
        let calendar = Calendar.current
        guard
            let from = calendar.date(byAdding: .year, value: -years, to: today),
            let to = calendar.date(byAdding: .year, value: years, to: today)
        else { return nil }
        return from...to
    }

    /// **목표선은 넓은 창에서만 그린다.** 좁은 창에서 수십억짜리 선을 그리면
    /// 그 하나 때문에 축이 늘어나 나머지가 전부 바닥에 눌린다.
    private var showsTarget: Bool {
        (span == .retirement || span == .all) && targetMinor > 0 && !showsReal
    }

    // MARK: - 축

    /// **바닥은 0이다.** 최솟값에서 시작하면 없는 기울기가 생겨 증감이 실제보다
    /// 커 보인다. 복리를 정직하게 보여주려면 바닥이 0이어야 한다.
    /// 순자산이 음수인 구간이 있으면 그때만 0 아래로 내린다.
    private var domain: ClosedRange<Double> {
        let values = visiblePoints.map { $0.value(real: showsReal) }
        var upper = values.max() ?? 0
        if showsTarget { upper = max(upper, Double(targetMinor)) }
        let lower = min(0, values.min() ?? 0)
        // 위쪽에 숨 쉴 틈을 둔다. 최고점이 천장에 닿으면 선이 잘려 보인다.
        return lower...max(upper * 1.08, lower + 1_000_000)
    }

    /// 축 눈금 글자. 눈금은 대개 딱 떨어지는 값이라 `60.0억` 이 아니라 `60억` 이다.
    /// 소수가 필요할 때만 한 자리를 붙인다.
    private func axisLabel(_ raw: Double) -> String {
        let value = Int(raw)
        let eok = 100_000_000
        guard value >= eok else {
            return Won.compact(Money(minorUnits: value, currency: .krw))
        }
        let tenths = (value * 10 + eok / 2) / eok
        let text = tenths % 10 == 0 ? "\(tenths / 10)억" : "\(tenths / 10).\(tenths % 10)억"
        return AmountPrivacy.mask(text)
    }

    /// 기간이 길면 눈금을 성기게 둔다.
    private var xStride: Int {
        guard let first = visiblePoints.first?.date, let last = visiblePoints.last?.date
        else { return 5 }
        let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
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
