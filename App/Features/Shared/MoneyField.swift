import Core
import SwiftUI

/// 원 단위 금액 입력. 입력하는 동안 자릿수 구분이 따라붙는다.
///
/// 주간 점검에서 반복해 쓰는 부품이라 여기서 한 번만 만든다.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int
    var placeholder: String = "0"

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
            Text("원")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
        }
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
