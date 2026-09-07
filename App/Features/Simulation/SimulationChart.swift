import Charts
import Core
import Foundation
import SwiftUI

/// 네 시나리오를 한 축에 겹쳐 그린다 (docs/08-feedback.md 34·35번).
///
/// 예전에는 밴드(면) 하나에 가운데 선을 얹었는데, **세 선의 금액이 전부 같아서**
/// 면의 두께가 0이었다 — 화면에는 선 하나만 보였다. 원인은 계산 쪽이었고
/// (`ProjectionInput.settingInvestmentReturn` 주석 참고), 고치고 나니 이제
/// 네 줄이 뚜렷하게 갈린다. 그래서 면 대신 **선 넷**으로 그린다.
///
/// **Y축은 로그다.** 궤적 차트는 선형으로 바꿨지만(31번) 이 화면은 다른 질문에
/// 답한다 — 여기서 보는 것은 "얼마가 되나" 가 아니라 **"가정에 따라 몇 배로
/// 갈리나"** 다. 연 3%와 연 20%는 23년이면 열 배 넘게 벌어지는데, 선형 축에
/// 담으면 아래 세 줄이 전부 바닥에 붙어 비교 자체가 안 된다.
struct SimulationChart: View {

    /// 네 시나리오. 순서가 곧 화면의 순서이고 색도 여기서 정해진다.
    enum ScenarioKind: String, CaseIterable, Sendable, Identifiable {
        /// 물가상승률만큼만 번다고 볼 때.
        case conservative
        /// 계획 탭에 저장해 둔 값 그대로.
        case plan
        /// 지금 손잡이를 돌려 둔 값.
        case current
        /// 연 20%. 사용자가 부르는 이름은 `장미빛 전망` 이다.
        case optimistic

        var id: String { rawValue }

        var label: String {
            switch self {
            case .conservative: return "보수적"
            case .plan: return "계획대로"
            case .current: return "이 설정"
            case .optimistic: return "장미빛"
            }
        }

        /// **네 색이 서로 확실히 달라야 한다** (35번). 금액이 비슷해질 때도
        /// 어느 선이 어느 시나리오인지 색만으로 갈라져야 한다.
        var color: Color {
            switch self {
            case .conservative: return .loss     // 붉은 계열 — 낮은 쪽
            case .plan: return .faint            // 회색 — 비교 기준
            case .current: return .dad           // 파랑 — 지금 돌리는 것
            case .optimistic: return .gain       // 초록 — 높은 쪽
            }
        }

        /// 지금 돌리는 선이 가장 굵다. 눈이 먼저 가야 하는 줄이다.
        var lineWidth: CGFloat { self == .current ? 2.6 : 1.6 }

        /// 계획선만 점선이다 — 나머지는 "이 가정이면" 이고 이것만 "지금 계획" 이다.
        var dash: [CGFloat] { self == .plan ? [4, 3] : [] }
    }

    struct LinePoint: Identifiable, Hashable, Sendable {
        let date: Date
        let minor: Int

        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    struct Series: Identifiable, Hashable, Sendable {
        let kind: ScenarioKind
        let points: [LinePoint]

        var id: String { kind.rawValue }
    }

    let series: [Series]
    let targetMinor: Int
    /// 은퇴 시점. **큰 숫자가 가리키는 자리**다 — 차트는 지평선까지 그리므로
    /// 표시가 없으면 헤드라인의 `2049년 63억` 과 선의 끝값(수백억)이 어긋나
    /// 보인다.
    var retirementDate: Date? = nil
    /// 자산이 바닥나는 시점. 있으면 차트가 그것을 말해야 한다 —
    /// 예전에는 선이 아래로 도망갈 뿐 아무 설명이 없었다 (docs/08-feedback.md 3번).
    var depletion: Date? = nil

    private static let ticks: [Int] = [
        1_000_000, 3_000_000, 10_000_000, 30_000_000,
        100_000_000, 300_000_000, 1_000_000_000, 3_000_000_000,
        10_000_000_000, 30_000_000_000, 100_000_000_000
    ]

    private func logScale(_ minor: Int) -> Double { log10(max(Double(minor), 1_000_000)) }

    var body: some View {
        if series.allSatisfy({ $0.points.count < 2 }) {
            placeholder
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("시점", point.date),
                        y: .value("예상", logScale(point.minor)),
                        series: .value("구분", line.kind.label)
                    )
                    .foregroundStyle(line.kind.color)
                    .lineStyle(StrokeStyle(lineWidth: line.kind.lineWidth,
                                           lineCap: .round,
                                           dash: line.kind.dash))
                    .interpolationMethod(.monotone)
                }
            }

            if targetMinor > 0 {
                RuleMark(y: .value("목표", logScale(targetMinor)))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            }

            if let retirementDate {
                RuleMark(x: .value("은퇴", retirementDate))
                    .foregroundStyle(Color.ruleStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("은퇴")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.muted)
                    }
            }

            if let depletion {
                RuleMark(x: .value("고갈", depletion))
                    .foregroundStyle(Color.loss.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("바닥")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color.loss)
                    }
            }
        }
        .chartYScale(domain: domain)
        // 도메인 밖으로 나간 선이 차트를 벗어나 **아래 카드 위에 그려지던** 문제.
        // 적립 0원이면 예상선이 곤두박질치는데, 잘라 주지 않으면 화면이 깨져 보인다.
        .chartPlotStyle { plot in plot.clipped() }
        .chartYAxis {
            AxisMarks(values: tickValues) { value in
                AxisGridLine().foregroundStyle(Color.rule)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(tickLabel(raw))
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
        .frame(height: 176)
    }

    private var placeholder: some View {
        Text("계획 탭에서 월 적립액과 기대수익률을 먼저 넣어 주세요")
            .font(.system(size: 12))
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 176)
    }

    /// 로그 축에서 아래위로 몇 자릿수까지 보여줄 것인가.
    /// 고갈하면 예상선이 바닥(100만원)까지 내려가는데, 그대로 다 담으면
    /// 위쪽이 납작해져 읽을 수 없게 된다. 다섯 자릿수에서 끊는다.
    private static let maxDecades: Double = 5

    private var domain: ClosedRange<Double> {
        var values = series.flatMap { $0.points.map { logScale($0.minor) } }
        if targetMinor > 0 { values.append(logScale(targetMinor)) }
        let upper = (values.max() ?? 9) + 0.15
        let lower = max((values.min() ?? 6) - 0.15, upper - Self.maxDecades)
        return lower...max(upper, lower + 0.5)
    }

    private var tickValues: [Double] {
        Self.ticks.map { log10(Double($0)) }.filter { domain.contains($0) }
    }

    private func tickLabel(_ logValue: Double) -> String {
        let amount = Int(pow(10, logValue).rounded())
        if amount >= 100_000_000 { return AmountPrivacy.mask("\(amount / 100_000_000)억") }
        if amount >= 10_000 { return AmountPrivacy.mask("\(amount / 10_000)만") }
        return AmountPrivacy.mask("\(amount)")
    }

    /// 23년 구간에서 10년 간격이면 눈금이 두 개만 남아 언제쯤인지 가늠이 안 된다.
    private var xStride: Int {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max() else { return 5 }
        let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
        return years < 8 ? 2 : (years < 32 ? 5 : 10)
    }
}
