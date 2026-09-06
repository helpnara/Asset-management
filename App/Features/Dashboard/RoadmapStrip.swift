import Core
import SwiftUI

/// 전체 자산 로드맵 — 1페이지 상단의 그 타임라인.
///
/// **가로 레일이다.** 선 위에 점 여섯 개를 찍고, 지금이 어디쯤인지 채워서 보여준다.
/// 예전에는 칸마다 연도·금액·라벨을 세로로 쌓아 가로로 스크롤했는데,
/// 사용자 마일스톤까지 섞이면서 길이가 제한 없이 늘어났다
/// (docs/08-feedback.md 5번).
///
/// 금액을 여섯 개 다 보여주지 않는 이유는, 정거장이 뼈대로 고정되고 나면
/// **"언제 무엇이 오는가"** 가 요점이기 때문이다. 금액은 `지금` 과 `은퇴` 만
/// 적고 나머지는 눌러서 본다.
struct RoadmapStrip: View {

    /// 이 정거장이 지나갔는가, 앞에 있는가, 오지 않는가.
    enum State: Hashable {
        case passed     // 이미 지났다
        case ahead      // 앞에 있다
        case never      // 이 계획으로는 오지 않는다
    }

    struct Stop: Identifiable, Hashable {
        /// 오지 않는 정거장은 연도가 없다. **칸은 그대로 둔다** — 사라지면
        /// 뼈대가 흔들려 매번 다른 그림이 된다.
        let year: Int?
        let amount: Money?
        let label: String
        let isNow: Bool
        let isGoal: Bool
        var state: State = .ahead

        var id: String { "\(label)-\(year.map(String.init) ?? "—")" }
    }

    let stops: [Stop]

    @State private var selected: Stop.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rail
            if let stop = stops.first(where: { $0.id == selected }), let amount = stop.amount {
                Text("\(stop.label) · \(stop.year.map(String.init) ?? "—")년 · \(Won.compact(amount))")
                    .font(.figure(11))
                    .foregroundStyle(Color.bodyText)
                    .transition(.opacity)
            }
        }
    }

    private var rail: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                VStack(spacing: 4) {
                    Text(stop.year.map { String($0) } ?? "—")
                        .font(.figure(9))
                        .foregroundStyle(yearColor(stop))

                    // 점과 점 사이를 잇는 선. 지나온 구간은 진하게 남긴다.
                    ZStack {
                        HStack(spacing: 0) {
                            segment(filled: index > 0 && stop.state != .never)
                            segment(filled: index < stops.count - 1 && nextIsPassed(index))
                        }
                        dot(stop)
                    }
                    .frame(height: 12)

                    Text(stop.label)
                        .font(.system(size: 8.5, weight: stop.isNow ? .semibold : .regular))
                        .foregroundStyle(labelColor(stop))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // 금액은 두 곳만. 여섯 개를 동시에 읽을 일은 드물다.
                    if stop.isNow || stop.isGoal, let amount = stop.amount {
                        Text(Won.compact(amount))
                            .font(.figure(11, weight: .bold))
                            .foregroundStyle(stop.isNow ? Color.dad : Color.ink)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selected = selected == stop.id ? nil : stop.id
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func segment(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.dad.opacity(0.55) : Color.rule)
            .frame(height: 1.5)
    }

    private func dot(_ stop: Stop) -> some View {
        Circle()
            .fill(dotFill(stop))
            .frame(width: stop.isNow ? 11 : 8, height: stop.isNow ? 11 : 8)
            .overlay(
                Circle().stroke(stop.state == .never ? Color.ruleStrong : Color.dad,
                                lineWidth: stop.state == .never ? 1 : 0)
            )
    }

    /// 이 정거장 다음 구간을 채울지. 지금보다 앞선 곳까지만 채운다.
    private func nextIsPassed(_ index: Int) -> Bool {
        guard index + 1 < stops.count else { return false }
        return stops[index].isNow || stops[index].state == .passed
    }

    private func dotFill(_ stop: Stop) -> Color {
        switch stop.state {
        case .never: return .canvas
        case .passed: return .dad.opacity(0.55)
        case .ahead: return stop.isNow ? .dad : (stop.isGoal ? .ink : .ruleStrong)
        }
    }

    private func yearColor(_ stop: Stop) -> Color {
        if stop.isNow { return .dad }
        return stop.state == .never ? .faint.opacity(0.6) : .faint
    }

    private func labelColor(_ stop: Stop) -> Color {
        if stop.isNow { return .dad }
        return stop.state == .never ? .faint : .muted
    }
}
