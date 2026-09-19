import SwiftUI

/// **누르는 즉시 화면 값만 바꾸고, 모델에는 손을 멈춘 뒤 한 번 쓰는 손잡이**
/// (docs/08-feedback.md 166 · 169번).
///
/// `Stepper` 를 모델에 직접 묶으면 한 칸 누를 때마다 저장소가 바뀌고, 살아 있는
/// 탭 전부가 다시 그려지고, 자동 저장과 궤적 계산이 그 자리에서 시작된다 —
/// 그래서 버튼이 멈칫거렸다. 여기서는 누르는 동안 `draft` 만 움직이고,
/// 250ms 동안 손이 안 오면 그때 한 번 `value` 에 쓴다. 쓰기 전까지는 아래
/// 띠에 `반영 중` 이 켜진다.
///
/// 퍼센트 손잡이(`PercentStepper`), 가족 자산 배분 · 계좌 목표의 비중 손잡이,
/// 계획 탭의 "보는 기간" 이 전부 이것 하나를 쓴다. **모델에 직접 묶인
/// `Stepper` 를 새로 만들지 않는다.**
struct DeferredStepper<Label: View>: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var delay: Duration = .milliseconds(250)
    /// 지금 보이는 값(누르는 동안은 `draft`)을 받아 그린다.
    @ViewBuilder var label: (Int) -> Label

    @State private var draft: Int?
    @State private var commit: Task<Void, Never>?

    private var shown: Int { draft ?? value }

    var body: some View {
        Stepper(value: Binding(get: { shown }, set: { next in
            draft = next
            commit?.cancel()
            commit = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let pending = draft else { return }
                value = pending
                draft = nil
            }
        }), in: range, step: step) {
            label(shown)
        }
        .reportsProgress("반영 중", when: draft != nil)
    }
}
