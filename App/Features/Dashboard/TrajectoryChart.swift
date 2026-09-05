import Charts
import Core
import Foundation
import SwiftUI

/// 순자산 궤적 — 이 앱이 존재하는 이유.
///
/// 왼쪽은 매주 직접 적어 넣은 **사실**, 오른쪽은 가정에 따른 **추정**이다.
/// 둘을 같은 축 위에 잇되 실선과 점선으로 절대 섞이지 않게 그린다 (설계 2.2.3).
///
/// Y축은 로그다. 20년 넘는 복리를 선형으로 그리면 앞 10년이 바닥에 붙어 보이지 않는다.
/// 로그 축에서는 일정 비율 성장이 직선이 되어 계획선에서 벗어나는 것도 눈에 띈다.
struct TrajectoryChart: View {

    struct Point: Identifiable, Hashable {
        enum Series: String {
            case actual = "실제 기록"
            case projected = "예측"
        }
        let date: Date
        let minor: Int
        let series: Series

        var id: String { "\(series.rawValue)-\(date.timeIntervalSince1970)" }
        /// 로그 변환. 100만원을 바닥으로 둬서 0이나 음수에서 무너지지 않게 한다.
        var logValue: Double { log10(max(Double(minor), 1_000_000)) }
    }

    let points: [Point]
    let today: Date
    let targetMinor: Int

    /// 1·3 배수를 함께 둔다. 10의 거듭제곱만 쓰면 로그 축에서 눈금이 하나만 남는다.
    private static let ticks: [Int] = [
        1_000_000, 3_000_000, 10_000_000, 30_000_000,
        100_000_000, 300_000_000, 1_000_000_000, 3_000_000_000, 10_000_000_000
    ]

    var body: some View {
        if points.count < 2 {
            placeholder
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("시점", point.date),
                    y: .value("순자산", point.logValue),
                    series: .value("구분", point.series.rawValue)
                )
                .foregroundStyle(point.series == .actual ? Color.ink : Color.dad)
                .lineStyle(StrokeStyle(
                    lineWidth: point.series == .actual ? 2.2 : 1.8,
                    lineCap: .round,
                    dash: point.series == .actual ? [] : [4, 3]
                ))

                // 은퇴까지를 보면 과거 몇 달은 전체 폭의 1%도 안 되어 선이 사라진다.
                // 점을 함께 찍어야 "실제로 적어 온 기록"이 눈에 남는다.
                if point.series == .actual {
                    PointMark(
                        x: .value("시점", point.date),
                        y: .value("순자산", point.logValue)
                    )
                    .foregroundStyle(Color.ink)
                    .symbolSize(20)
                }
            }

            // 목표선에는 주석을 달지 않는다. 차트 주석은 leading 이든 trailing 이든
            // 가장자리에서 잘린다. 라벨은 범례 줄에 둔다.
            if targetMinor > 0 {
                RuleMark(y: .value("목표", log10(max(Double(targetMinor), 1_000_000))))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            }

            RuleMark(x: .value("오늘", today))
                .foregroundStyle(Color.ink)
                .lineStyle(StrokeStyle(lineWidth: 1))
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

    // MARK: - 축

    private var domain: ClosedRange<Double> {
        let values = points.map(\.logValue)
        let lower = (values.min() ?? 6) - 0.15
        var upper = (values.max() ?? 9) + 0.15
        if targetMinor > 0 {
            upper = max(upper, log10(Double(targetMinor)) + 0.1)
        }
        return lower...max(upper, lower + 0.5)
    }

    private var tickValues: [Double] {
        Self.ticks
            .map { log10(Double($0)) }
            .filter { domain.contains($0) }
    }

    /// 눈금은 정확한 거듭제곱이라 소수를 붙이지 않는다. `1.0억` 이 아니라 `1억`.
    private func tickLabel(_ logValue: Double) -> String {
        let amount = Int(pow(10, logValue).rounded())
        if amount >= 100_000_000 { return "\(amount / 100_000_000)억" }
        if amount >= 10_000 { return "\(amount / 10_000)만" }
        return "\(amount)"
    }

    /// 기간이 길면 눈금을 성기게 둔다.
    private var xStride: Int {
        guard let first = points.first?.date, let last = points.last?.date else { return 5 }
        let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
        switch years {
        case ..<3: return 1
        case ..<8: return 2
        case ..<20: return 5
        default: return 10
        }
    }
}
