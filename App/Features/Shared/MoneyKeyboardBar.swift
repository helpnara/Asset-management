import SwiftUI

/// **금액 칸 위의 `만 · 억 · 완료` 띠** (152번 3-1).
///
/// 예전에는 `MoneyField` 마다 `ToolbarItemGroup(placement: .keyboard)` 로 달았다.
/// 그 줄은 **iOS 가 키보드에 얹어 주는 것**이라 우리가 그리는 것이 아니고,
/// 주간 점검에서 실제로 문제가 됐다 — 커서가 줄을 옮겨 다니면 iOS 가 자동 완성
/// 알약을 대신 띄우거나 줄을 통째로 떼어 버렸고("보였다 안 보였다", 144번),
/// 글자 크기를 바꿔도 다시 그려지지 않았다. 그래서 주간 점검은 **화면 안에 우리가
/// 직접 그리는 띠**(`safeAreaInset`)로 옮겼고, 여기서 나머지 화면도 같은 꼴로 맞춘다.
///
/// 한 가지 더. SwiftUI 는 한 화면의 `.keyboard` 툴바를 **전부 합쳐** 한 줄에
/// 늘어놓는다. 그래서 부품마다 `if isFocused` 로 막아야 했고, 그 방어가 없던
/// 빌드 13 에서 계획 탭에 `완료` 가 네 개 떴다. 띠가 하나면 그 문제가 없다.
///
/// **쓰는 법.** 금액 칸이 있는 화면(시트면 시트 뿌리)에 `.moneyKeyboardBar()` 를
/// 붙인다. 붙이지 않아도 입력은 되고, 띠만 안 뜬다 — 크래시로 벌주지 않는다.
@MainActor
@Observable
final class MoneyKeyboard {
    static let shared = MoneyKeyboard()

    /// 지금 커서가 있는 금액 칸이 띠에 건네는 손잡이.
    struct Handle {
        let id: UUID
        /// `만` · `억` — 12 → 만 → 120,000.
        ///
        /// **칸이 바인딩만 잡아 만든다** (156번). 예전에는 `MoneyField` 라는
        /// 구조체 값의 메서드를 통째로 건넸는데, 그러면 손잡이가 커서 들어온
        /// 순간의 사본에 묶인다. 그리고 이 함수는 모델뿐 아니라 **칸의 글자까지**
        /// 바꿔야 한다 — 커서가 있는 칸은 모델 값을 다시 읽지 않기 때문이다.
        let multiply: @MainActor (Int) -> Void
        /// 숫자 키패드에는 return 키가 없다. 내리는 길을 띠가 낸다.
        let focus: FocusState<Bool>.Binding
    }

    private(set) var active: Handle?

    func activate(_ handle: Handle) { active = handle }

    /// **자기 것일 때만 지운다.** 칸에서 칸으로 옮길 때 새 칸이 먼저 잡고
    /// 옛 칸이 뒤늦게 놓는 순서가 되는데, 그때 남의 손잡이를 지우면 띠가
    /// 깜빡인다 — 144번에서 고친 그 증상이 여기서 되살아난다.
    func resign(_ id: UUID) {
        if active?.id == id { active = nil }
    }
}

extension View {
    func moneyKeyboardBar() -> some View {
        modifier(MoneyKeyboardBarModifier())
    }
}

struct MoneyKeyboardBarModifier: ViewModifier {
    @State private var keyboard = MoneyKeyboard.shared
    /// 글자가 커지면 `만 · 억` 은 접고 `완료` 만 남긴다 — 주간 점검 띠와 같은 규칙.
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let active = keyboard.active {
                HStack(spacing: 14) {
                    if typeSize < .accessibility1 {
                        Button("만") { active.multiply(10_000) }
                            .font(.scaled(14))
                        Button("억") { active.multiply(100_000_000) }
                            .font(.scaled(14))
                    }
                    Spacer(minLength: 0)
                    Button("완료") { active.focus.wrappedValue = false }
                        .font(.scaled(15, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.surface)
                .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .top)
                .tint(Color.ink)
            }
        }
    }
}
