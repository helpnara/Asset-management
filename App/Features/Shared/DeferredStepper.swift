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
    /// 초안이 생기거나 사라질 때 부모에게 알린다 (169번 후속). 손잡이 밖의 라벨
    /// (`75/40%` 같은 비중 표기)이 모델이 아니라 초안을 그리게 하려는 것이다 —
    /// 모델이 따라오기 전까지 화면이 안 움직이면 "안 눌린다" 로 읽힌다.
    var onDraft: ((Int?) -> Void)? = nil
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
                // **모델이 따라온 것을 보고서야 초안을 내린다.** 바로 내리면 다음
                // 누름이 아직 옛 값을 든 바인딩에서 출발해 한 칸이 사라진다 —
                // 빌드 97 에서 두 번째 누름부터 안 먹던 것이 그것이다.
                if value == pending { draft = nil }
            }
        }), in: range, step: step) {
            label(shown)
        }
        .onChange(of: value) { _, latest in
            if let draft, draft == latest { self.draft = nil }
        }
        .onChange(of: draft) { _, latest in onDraft?(latest) }
        .reportsProgress("반영 중", when: draft != nil)
    }
}
