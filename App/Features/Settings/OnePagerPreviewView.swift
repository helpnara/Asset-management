import Core
import CoreData
import SwiftUI

/// 1페이지를 뽑기 전에 화면에서 본다.
///
/// **이 화면이 없어서 개수를 감으로 정할 뻔했다** (docs/08-feedback.md 24번).
/// 원칙을 몇 개 실을지, 구성원 카드에 종목을 몇 줄까지 둘지는 "한 장에
/// 들어가느냐" 로 정해지는데, 원격 세션에서는 스크린샷이 유일한 확인 창구다.
/// 다른 화면은 전부 CI 가 찍는데 정작 이 화면만 빠져 있었다.
///
/// 종이 크기(A4 595×842pt)를 그대로 그리고 **한 장 끝 선**을 함께 그어,
/// 넘치면 넘친 만큼이 눈에 보이게 한다.
struct OnePagerPreviewView: View {
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched private var holdings: [Holding]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \Principle.order) private var principles: [Principle]
    @Fetched(sort: \TodoItem.sortIndex) private var todos: [TodoItem]
    @Fetched(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]

    /// A4 @72dpi. `OnePagerView` 의 폭과 같은 값이라야 미리보기가 거짓말을 안 한다.
    private let paperWidth: CGFloat = 595
    private let paperHeight: CGFloat = 842
    /// 위쪽 안내 문구가 앉을 자리. 글자가 커지면 같이 커진다 — 고정 38pt 였을 때
    /// 큰 글자에서 문구가 종이 위로 겹쳤다 (132번, 빌드 69 확인 6).
    private var captionHeight: CGFloat { Font.scaledLength(38) * 1.15 }

    /// **손가락으로 확대** (137번). 폭 맞춤(1배)에서 4배까지. 두 번 두드리면
    /// 2.5배와 1배를 오간다. 확대하면 가로로도 스크롤된다.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// 잰 종이 높이(줄이기 전). 확대했을 때 스크롤 영역을 종이 크기에 맞추려면 필요하다.
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let fit = max(0.1, (proxy.size.width - 24) / paperWidth)
            let scale = fit * min(max(zoom * pinch, 1), 4)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 10) {
                    // 안내 문구는 아래 `overlayPreferenceValue` 가 채운다.
                    Color.clear.frame(height: captionHeight)
                    page(scale: scale)
                        .frame(height: max(measuredHeight, paperHeight) * scale, alignment: .topLeading)
                }
                .padding(12)
                .overlayPreferenceValue(PageHeightKey.self) { height in
                    caption(pageHeight: height)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                // Swift 6: 이 클로저는 Sendable 이라 @State 를 바로 못 고친다.
                .onPreferenceChange(PageHeightKey.self) { height in
                    Task { @MainActor in measuredHeight = height }
                }
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 4) }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { zoom = zoom > 1 ? 1 : 2.5 }
            }
        }
        .background(Color.ground)
        .navigationTitle("한 장 미리보기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(scale: CGFloat) -> some View {
        OnePagerBuilder.make(plan: plans.first, members: members, holdings: holdings,
                             cashEvents: cashEvents, incomes: incomes,
                             principles: principles, todos: todos, snapshots: snapshots)
            // 재는 것은 **줄이기 전**이다. `scaleEffect` 뒤에 재면 축소된 값이 나온다.
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PageHeightKey.self, value: geometry.size.height)
                }
            }
            .overlay(alignment: .top) {
                // 한 장이 끝나는 자리. 이 선 아래로 내려간 것은 둘째 장이다.
                Rectangle()
                    .fill(Color.loss)
                    .frame(width: paperWidth, height: 1)
                    .offset(y: paperHeight)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: paperWidth * scale, alignment: .topLeading)
    }

    private func caption(pageHeight: CGFloat) -> some View {
        let overflows = pageHeight > paperHeight + 0.5
        return VStack(alignment: .leading, spacing: 3) {
            Text(fitText(pageHeight: pageHeight, overflows: overflows))
                .font(.scaled(13, weight: .semibold))
                .foregroundStyle(overflows ? Color.loss : Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("A4 한 장은 595 × 842pt 입니다. 빨간 선이 한 장이 끝나는 자리입니다.")
                .font(.scaled(11))
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fitText(pageHeight: CGFloat, overflows: Bool) -> String {
        guard pageHeight > 0 else { return "그리는 중…" }
        let filled = Int((pageHeight / paperHeight * 100).rounded())
        if overflows {
            return "한 장을 \(Int((pageHeight - paperHeight).rounded()))pt 넘습니다 (\(filled)%)"
        }
        return "한 장에 들어갑니다 — \(filled)% 찼습니다"
    }
}

private struct PageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
