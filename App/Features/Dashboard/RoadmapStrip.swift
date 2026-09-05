import Core
import SwiftUI

/// 전체 자산 로드맵 — 1페이지 상단의 그 타임라인.
///
/// 금액보다 라벨이 중요하다. "수익 > 적립금" 같은 교차점이 동기를 만든다.
struct RoadmapStrip: View {

    struct Stop: Identifiable, Hashable {
        let year: Int
        let amount: Money
        let label: String
        let isNow: Bool
        let isGoal: Bool
        var id: Int { year }
    }

    let stops: [Stop]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(stop.year)")
                            .font(.figure(10))
                            .tracking(1)
                            .foregroundStyle(stop.isNow ? Color.dad : Color.faint)

                        Text(Won.compact(stop.amount))
                            .font(.figure(stop.isNow || stop.isGoal ? 15 : 13,
                                          weight: stop.isNow || stop.isGoal ? .bold : .semibold))
                            .foregroundStyle(amountColor(stop))
                            .padding(.top, 5)

                        Text(stop.label)
                            .font(.system(size: 9))
                            .foregroundStyle(stop.isNow ? Color.dad : Color.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                    .frame(width: 78, alignment: .leading)
                    .padding(.leading, index == 0 ? 0 : 9)
                    .padding(.trailing, 5)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle().fill(Color.rule).frame(width: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func amountColor(_ stop: Stop) -> Color {
        if stop.isNow { return .dad }
        if stop.isGoal { return .ink }
        return .bodyText
    }
}
