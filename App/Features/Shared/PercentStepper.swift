import Core
import SwiftUI

/// basis point 를 퍼센트로 보여주며 오르내리는 줄.
///
/// 계좌 기대수익률·목표 비중·계획의 가정이 전부 같은 모양을 쓴다.
/// 화면마다 따로 만들었다가 한 곳에서만 고치면 나머지가 어긋난다.
struct PercentStepper: View {
    let title: String
    @Binding var basisPoints: Int
    var range: ClosedRange<Int> = 0...10_000
    var step: Int = 250

    var body: some View {
        Stepper(value: $basisPoints, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                // 1%p 단위로 움직이면 정수로 적는다 (docs/08-feedback.md 18번).
                Text(step % 100 == 0
                     ? "\(PercentFormatter.integer(Decimal(basisPoints) / 10_000))%"
                     : "\(PercentFormatter.oneDecimal(Decimal(basisPoints) / 10_000))%")
                    .font(.figure(14, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}
