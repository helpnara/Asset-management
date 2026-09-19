import Core
import SwiftUI

/// basis point 를 퍼센트로 보여주며 오르내리는 줄.
///
/// 계좌 기대수익률·목표 비중·계획의 가정·진단 기준이 전부 같은 모양을 쓴다.
/// 화면마다 따로 만들었다가 한 곳에서만 고치면 나머지가 어긋난다 — 실제로
/// 계획 탭과 진단 기준이 제 것을 따로 갖고 있었다 (166번에서 여기로 합쳤다).
///
/// **누르는 즉시 숫자만 바꾸고, 모델에는 손을 멈춘 뒤에 쓴다** (166번).
/// 손잡이를 모델에 직접 묶어 두면 한 칸 누를 때마다 저장소가 바뀌고, 살아
/// 있는 탭 전부가 다시 그려지고, 궤적 계산이 다시 시작된다 — **그 자리에서**.
/// 그래서 버튼이 멈칫거렸다. 누르는 동안은 화면 안의 `draft` 만 움직이고,
/// 250ms 동안 손이 안 오면 그때 한 번 모델에 쓴다. 금액 칸(`MoneyField`)이
/// 156번에서 배운 것과 같은 꼴이다.
///
/// 아직 안 쓴 값이 있는 동안은 **아래 띠**에 `반영 중` 이 켜진다 (169번). 예전에는
/// 숫자 옆에 회전 아이콘을 끼웠는데, 아이콘이 끼어들며 숫자를 옆으로 밀어
/// 줄이 들썩였다. 띠는 본문을 안 건드린다.
struct PercentStepper: View {
    let title: String
    @Binding var basisPoints: Int
    var range: ClosedRange<Int> = 0...10_000
    var step: Int = 250

    /// 누르는 동안의 값. `nil` 이면 모델 그대로다.
    @State private var draft: Int?
    @State private var commit: Task<Void, Never>?

    private var shown: Int { draft ?? basisPoints }

    var body: some View {
        Stepper(value: Binding(get: { shown }, set: { next in
            draft = next
            commit?.cancel()
            commit = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let value = draft else { return }
                basisPoints = value
                draft = nil
            }
        }), in: range, step: step) {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                // 1%p 단위로 움직이면 정수로 적는다 (docs/08-feedback.md 18번).
                Text(step % 100 == 0
                     ? "\(PercentFormatter.integer(Decimal(shown) / 10_000))%"
                     : "\(PercentFormatter.oneDecimal(Decimal(shown) / 10_000))%")
                    .font(.figure(14, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
        }
        .reportsProgress("반영 중", when: draft != nil)
    }
}
