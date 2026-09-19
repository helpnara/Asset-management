import SwiftUI

/// **계산 중임을 화면 어디에서든 보이게** (docs/08-feedback.md 166번).
///
/// 계획 탭의 `반영 중` 은 맨 위 요약 안에만 있었다. 수익률 구역까지 내려가
/// 손잡이를 누르는 사람에게는 안 보였고, 안 보이니 "왜 안 되지" 하며
/// 계속 눌렀다. 아래에 붙는 띠는 스크롤과 무관하게 보인다.
///
/// 문구는 하나다 — `반영 중`. "잠시만 기다리세요" 같은 부탁은 안 적는다.
/// 무엇을 하고 있는지만 보이면 사람은 기다린다.
struct RecalculatingBar: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if isActive {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("반영 중")
                        .font(.scaled(12, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.surface)
                .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .top)
            }
        }
    }
}

extension View {
    /// 계산이 도는 동안 아래에 `반영 중` 띠를 붙인다 (166번).
    func recalculatingBar(_ isActive: Bool) -> some View {
        modifier(RecalculatingBar(isActive: isActive))
    }
}
