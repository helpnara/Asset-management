import Charts
import Core
import Foundation
import SwiftUI

/// 신뢰구간 밴드 — "이대로 가면 얼마"가 아니라 "얼마쯤에서 얼마쯤 사이"를 그린다.
///
/// 궤적 차트(`TrajectoryChart`)가 한 줄을 그린다면 여기는 폭을 그린다.
/// 폭이 이 화면의 메시지다: 23년 뒤 숫자는 점이 아니라 구간이다.
/// Y축이 로그인 이유는 궤적 차트와 같다 — 선형으로는 앞 10년이 바닥에 붙는다.
struct SimulationChart: View {

    struct Band: Identifiable, Hashable, Sendable {
        let date: Date
        let low: Int
        let mid: Int
        let high: Int

        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    struct LinePoint: Identifiable, Hashable, Sendable {
        let date: Date
        let minor: Int

        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    /// 손잡이를 돌린 뒤의 밴드. `mid` 는 변동성을 뺀 예상선이다.
    let bands: [Band]
    /// 손잡이를 돌리기 전, 계획 그대로의 선. 비교 대상이 없으면 What-if 가 아니다.
    let baseline: [LinePoint]
    let targetMinor: Int

    private static let ticks: [Int] = [
        1_000_000, 3_000_000, 10_000_000, 30_000_000,
        100_000_000, 300_000_000, 1_000_000_000, 3_000_000_000,
        10_000_000_000, 30_000_000_000
    ]

    private func logScale(_ minor: Int) -> Double { log10(max(Double(minor), 1_000_000)) }

    var body: some View {
        if bands.count < 2 {
            placeholder
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(bands) { band in
                AreaMark(
                    x: .value("시점", band.date),
                    yStart: .value("하위 10%", logScale(band.low)),
                    yEnd: .value("상위 10%", logScale(band.high))
                )
                .foregroundStyle(Color.dad.opacity(0.16))
                .interpolationMethod(.monotone)
            }

            ForEach(bands) { band in
                LineMark(
                    x: .value("시점", band.date),
                    y: .value("예상", logScale(band.mid)),
                    series: .value("구분", "예상")
                )
                .foregroundStyle(Color.dad)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            ForEach(baseline) { point in
                LineMark(
                    x: .value("시점", point.date),
                    y: .value("계획 그대로", logScale(point.minor)),
                    series: .value("구분", "계획 그대로")
                )
                .foregroundStyle(Color.faint)
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                .interpolationMethod(.monotone)
            }

            if targetMinor > 0 {
                RuleMark(y: .value("목표", logScale(targetMinor)))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            }
        }
        .chartYScale(domain: domain)
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
            AxisMarks(values: .stride(by: .year, count: xStride)) { _ in
                AxisGridLine().foregroundStyle(Color.rule.opacity(0.6))
                AxisValueLabel(format: .dateTime.year(), centered: false)
                    .font(.figure(8))
                    .foregroundStyle(Color.faint)
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

    private var domain: ClosedRange<Double> {
        var values = bands.flatMap { [logScale($0.low), logScale($0.high)] }
        values.append(contentsOf: baseline.map { logScale($0.minor) })
        let lower = (values.min() ?? 6) - 0.15
        var upper = (values.max() ?? 9) + 0.15
        if targetMinor > 0 { upper = max(upper, logScale(targetMinor) + 0.1) }
        return lower...max(upper, lower + 0.5)
    }

    private var tickValues: [Double] {
        Self.ticks.map { log10(Double($0)) }.filter { domain.contains($0) }
    }

    private func tickLabel(_ logValue: Double) -> String {
        let amount = Int(pow(10, logValue).rounded())
        if amount >= 100_000_000 { return "\(amount / 100_000_000)억" }
        if amount >= 10_000 { return "\(amount / 10_000)만" }
        return "\(amount)"
    }

    /// 23년 구간에서 10년 간격이면 눈금이 두 개만 남아 언제쯤인지 가늠이 안 된다.
    private var xStride: Int {
        guard let first = bands.first?.date, let last = bands.last?.date else { return 5 }
        let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
        return years < 8 ? 2 : (years < 32 ? 5 : 10)
    }
}
