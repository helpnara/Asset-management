import Core
import SwiftUI

/// **순자산 궤적 크게 보기** (204번, 10-22 사용자: *"순자산궤적에 돋보기 같은 버튼을 하나 만들어서 크게
/// 자세히 볼 수 있는 기능을 하나 추가하자. 사용자 편의성 관점에서 기능을 고려해서"*).
///
/// 새 차트를 만들지 않는다 — 카드와 **같은 `TrajectoryChart`** 를 `isLarge` 로 그린다. 그래서 기간 ·
/// 오늘 돈 보기 · 금액 가리기 · 목표선 규칙이 카드와 어긋날 수 없다. 이 창이 더하는 것은:
/// - 화면 높이를 다 쓰는 차트 — 은퇴까지를 보아도 지금 몇 년이 바닥에 눌리지 않는다
/// - 큰 눈금 · 점 · 읽은 값, 손을 떼도 남는 짚은 시점
/// - 범례(카드에서는 차트 밖 현황판 몫이라 여기서 다시 적는다)
/// - 아이패드에서는 가로로 돌려 넓게 — 창은 탭 바깥에 떠서 돌려도 닫히지 않는다
struct TrajectoryDetailView: View {
    let content: TrajectoryChart.Expanded

    @Environment(\.dismiss) private var dismiss
    @AppStorage(TrajectoryChart.spanKey) private var span: TrajectoryChart.Span = .retirement
    @AppStorage(TrajectoryChart.realKey) private var showsReal = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TrajectoryChart(
                    points: content.points,
                    today: content.today,
                    targetMinor: content.targetMinor,
                    retirementDate: content.retirementDate,
                    events: content.events,
                    title: content.title,
                    isLarge: true
                )
                legend
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.raised)
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    /// 카드 아래 범례와 같은 내용 — 색과 선 모양은 차트가 쓰는 값을 그대로 읽는다.
    private var legend: some View {
        HStack(spacing: 16) {
            item(.actual)
            item(.projected)
            if content.points.contains(where: { $0.series == .plan }) {
                item(.plan)
            }
            // 목표선은 넓은 창 · 명목 보기에서만 그린다(차트의 `showsTarget` 과 같은 조건).
            if (span == .retirement || span == .all), content.targetMinor > 0, !showsReal {
                swatch(color: Color.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [1, 3]),
                       label: "목표 \(Won.compact(Money(minorUnits: content.targetMinor, currency: .krw)))")
            }
            Spacer(minLength: 0)
        }
    }

    private func item(_ series: TrajectoryChart.Point.Series) -> some View {
        swatch(color: TrajectoryChart.color(of: series), style: TrajectoryChart.stroke(of: series),
               label: series.rawValue)
    }

    private func swatch(color: Color, style: StrokeStyle, label: String) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: 20, y: 1.5))
            }
            .stroke(color, style: style)
            .frame(width: 20, height: 3)
            Text(label)
                .font(.scaled(11.5))
                .foregroundStyle(Color.muted)
        }
    }
}
