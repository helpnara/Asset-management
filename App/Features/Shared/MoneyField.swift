import Core
import SwiftUI

/// 원 단위 금액 입력. 입력하는 동안 자릿수 구분이 따라붙는다.
///
/// 주간 점검에서 반복해 쓰는 부품이라 여기서 한 번만 만든다.
///
/// **숫자 키패드에는 return 키가 없다.** 그래서 내리는 길을 부품이 직접 내준다 —
/// 키보드 위 `완료` 버튼이다. 이게 없으면 계획 탭처럼 시트도 내비게이션 바도
/// 없는 화면에서 키패드가 탭 바를 덮은 채 빠져나갈 수 없다
/// (docs/08-feedback.md 2번).
///
/// **`완료` 는 포커스를 가진 필드만 내놓는다.** SwiftUI 는 화면 안의
/// `placement: .keyboard` 툴바를 **전부 합쳐서** 한 줄에 늘어놓기 때문에,
/// 부품마다 무조건 선언하면 필드 수만큼 `완료` 가 생긴다. 빌드 13 에서
/// 계획 탭에 네 개가 떴다.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int
    var placeholder: String = "0"

    @FocusState private var isFocused: Bool

    private static let maxDigits = 15

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            field
            // **읽는 값** (docs/08-feedback.md 80번, B1). 원 단위 열다섯 자리를
            // 치다 0 하나 더 붙는 오타를 치는 순간 알아챈다. 입력 중에만 —
            // 목록마다 한 줄씩 늘어나면 화면이 무거워진다. 입력 칸이므로
            // 금액 가리기를 거치지 않는다 (`Won` 이 아니라 `KoreanAmountFormatter`).
            if isFocused && minorUnits >= 10_000 {
                Text(KoreanAmountFormatter.abbreviated(Money(minorUnits: minorUnits, currency: .krw), suffix: "원"))
                    .font(.figure(11, weight: .medium))
                    .foregroundStyle(Color.dad)
                    .transition(.opacity)
            }
        }
        // 라벨 아무 데나 눌러도 입력이 시작되게 한다. 오른쪽 끝 숫자만 겨우
        // 겨냥하는 것보다 손이 편하다.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .task {
            // CI 가 키보드 올라온 상태를 찍을 수 있게 하는 갈고리.
            // 이게 없으면 `완료` 버튼이 제대로 붙었는지 그림으로 확인할 방법이
            // 없다 — 실제로 빌드 13 에서 네 개가 생긴 것을 사용자가 먼저 봤다.
            guard MoneyField.shouldAutoFocus else { return }
            // **한 박자 뒤에 준다.** 화면이 뜨는 그 자리에서 바로 포커스를 주면
            // 키보드는 올라오는데 툴바가 그 변화를 못 받는 때가 있다 — 키패드
            // 위 줄이 빈 채로 찍힌다. 스물두 장 중 이 한 장만 빌드마다
            // 들쭉날쭉했던 이유이고, 7초를 더 기다려도 채워지지 않았다
            // (docs/09-family-sharing.md 1b-2). 사람이 탭할 때는 화면이 다
            // 선 뒤에 눌리므로 이 문제가 없다. 그 순서를 흉내 낸다.
            //
            // **1.2초인 이유.** 처음에 400ms 로 뒀더니 한 번은 잘 나오고 다음
            // 실행에는 또 없었다. 자동 저장의 디바운스가 마침 400ms 라 둘이
            // 같은 순간에 부딪친 것이다 — 저장이 컨텍스트를 흔들면 `@Fetched`
            // 가 다시 읽고, 그 사이에 툴바가 포커스 변화를 놓친다.
            // 화면이 완전히 가라앉은 뒤로 넉넉히 물린다. CI 전용 갈고리라
            // 사람이 쓸 때는 이 길로 오지 않는다.
            try? await Task.sleep(for: .milliseconds(1200))
            isFocused = true
        }
    }

    private var field: some View {
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
                        if isFocused {
                            // `만` · `억` (93번, B3). 12 → 만 → 120,000.
                            Button("만") { multiply(10_000) }
                                .font(.system(size: 14))
                            Button("억") { multiply(100_000_000) }
                                .font(.system(size: 14))
                            Spacer()
                            Button("완료") { isFocused = false }
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
            Text("원")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
        }
    }

    /// 실행 인자로 켜고, **맨 처음 나타나는 한 곳만** 포커스를 잡는다.
    @MainActor private static var didAutoFocus = false
    @MainActor private static var shouldAutoFocus: Bool {
        guard ProcessInfo.processInfo.arguments.contains("-focusMoneyField"),
              !didAutoFocus else { return false }
        didAutoFocus = true
        return true
    }

    private func multiply(_ factor: Int) {
        let next = minorUnits * factor
        guard minorUnits > 0, next < 1_000_000_000_000_000 else { return }
        minorUnits = next
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
