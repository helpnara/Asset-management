import Core
import SwiftData
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
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var plans: [Plan]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Query(sort: \Principle.order) private var principles: [Principle]
    @Query(sort: \TodoItem.sortIndex) private var todos: [TodoItem]

    /// A4 @72dpi. `OnePagerView` 의 폭과 같은 값이라야 미리보기가 거짓말을 안 한다.
    private let paperWidth: CGFloat = 595
    private let paperHeight: CGFloat = 842
    /// 위쪽 안내 문구가 앉을 자리.
    private let captionHeight: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let scale = max(0.1, (proxy.size.width - 24) / paperWidth)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 안내 문구는 아래 `overlayPreferenceValue` 가 채운다.
                    // 잰 높이를 상태로 받아 쓰지 않으려는 것이다 — 뷰 안에서
                    // 바로 읽어 그리면 상태 왕복도, 다시 그리기도 없다.
                    Color.clear.frame(height: captionHeight)
                    page(scale: scale)
                }
                .padding(12)
                .overlayPreferenceValue(PageHeightKey.self) { height in
                    caption(pageHeight: height)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(Color.ground)
        .navigationTitle("한 장 미리보기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(scale: CGFloat) -> some View {
        OnePagerBuilder.make(plan: plans.first, members: members, holdings: holdings,
                             cashEvents: cashEvents, incomes: incomes,
                             principles: principles, todos: todos)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(overflows ? Color.loss : Color.ink)
            Text("A4 한 장은 595 × 842pt 입니다. 빨간 선이 한 장이 끝나는 자리입니다.")
                .font(.system(size: 11))
                .foregroundStyle(Color.muted)
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
