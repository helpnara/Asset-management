import Core
import SwiftUI

/// 원 단위 금액 입력. 입력하는 동안 자릿수 구분이 따라붙는다.
///
/// 주간 점검에서 반복해 쓰는 부품이라 여기서 한 번만 만든다.
///
/// **숫자 키패드에는 return 키가 없다.** 그래서 내리는 길을 부품이 직접 내준다 —
/// 키보드 위 `완료` 버튼이다. 이게 없으면 계획 탭처럼 시트도 내비게이션 바도
/// 없는 화면에서 **키패드가 탭 바를 덮은 채 빠져나갈 수 없다**
/// (docs/08-feedback.md 2번). 이 부품이 6개 파일 14곳에서 쓰이므로
/// 여기 한 곳을 고치면 전부 함께 낫는다.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int
    var placeholder: String = "0"

    @FocusState private var isFocused: Bool

    private static let maxDigits = 15

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(Color.bodyText)
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.figure(17))
                .foregroundStyle(Color.ink)
                .focused($isFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("완료") { isFocused = false }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            Text("원")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
        }
        // 라벨 아무 데나 눌러도 입력이 시작되게 한다. 오른쪽 끝 숫자만 겨우
        // 겨냥하는 것보다 손이 편하다.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private var text: Binding<String> {
        Binding(
            get: { minorUnits == 0 ? "" : KoreanAmountFormatter.grouped(minorUnits) },
            set: { input in
                let digits = String(input.filter(\.isNumber).prefix(Self.maxDigits))
                minorUnits = Int(digits) ?? 0
            }
        )
    }
}
