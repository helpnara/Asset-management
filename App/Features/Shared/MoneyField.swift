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
/// **커서가 있는 동안에는 `draft` 가 칸의 글자다** (156번). 예전에는 칸이
/// `minorUnits` 에서 곧바로 글자를 만들었는데, 사람이 치는 동안에는 UIKit 이
/// 들고 있는 글자가 이긴다. 그래서 띠의 `만` 이 모델을 7,500,000 으로 바꿔도
/// 칸에는 `750` 이 남고 **다음 세터가 그 750 을 모델에 되썼다** — 눌러도 아무
/// 일이 안 일어나는 것처럼 보이던 것이 이 때문이다. 주간 점검은 이 문제를
/// 먼저 겪고 `draft` 로 풀었고(`WeeklyReviewView.valueText`), 띠를 화면 안으로
/// 옮길 때(152번 3-1) 그 장치만 안 따라왔다. 여기서 맞춘다.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int
    var placeholder: String = "0"

    @FocusState private var isFocused: Bool
    /// 이 칸을 띠가 알아보는 이름 (152번 3-1).
    @State private var fieldID = UUID()
    /// **커서가 있는 동안 칸이 보여 주는 글자.** 커서가 없으면 `nil` 이고,
    /// 그때는 모델 값에서 글자를 만든다.
    @State private var draft: String?
    /// 눌러도 아무 일이 안 일어날 때 잠깐 뜨는 한 줄. 말 없는 가드는 고장과
    /// 구별되지 않는다 (156번).
    @State private var note: String?

    private static let maxDigits = 13
    /// **1조 원.** 예전에는 1,000조였는데, 그 값이 목표 금액(× 25)과 23년
    /// 복리를 거치면 `Int` 밖으로 나가 앱이 켜지지 않았다 (159번).
    static let ceiling = MoneyLimits.maxMinorUnits

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            field
            // **읽는 값** (docs/08-feedback.md 80번, B1). 원 단위 열다섯 자리를
            // 치다 0 하나 더 붙는 오타를 치는 순간 알아챈다. 입력 중에만 —
            // 목록마다 한 줄씩 늘어나면 화면이 무거워진다. 입력 칸이므로
            // 금액 가리기를 거치지 않는다 (`Won` 이 아니라 `KoreanAmountFormatter`).
            if isFocused && currentValue >= 10_000 {
                Text(KoreanAmountFormatter.abbreviated(Money(minorUnits: currentValue, currency: .krw), suffix: "원"))
                    .font(.figure(11, weight: .medium))
                    .foregroundStyle(Color.dad)
                    .transition(.opacity)
            }
            if let note {
                Text(note)
                    .font(.scaled(10.5, weight: .medium))
                    .foregroundStyle(Color.loss)
                    .transition(.opacity)
            }
        }
        // 라벨 아무 데나 눌러도 입력이 시작되게 한다. 오른쪽 끝 숫자만 겨우
        // 겨냥하는 것보다 손이 편하다.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        // 한 줄짜리 알림은 스스로 사라진다. 지우는 버튼을 두면 그게 더 성가시다.
        .task(id: note) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            note = nil
        }
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
            // **`만` 을 눌러 본 컷** (156번). 이 버그는 "눌렀는데 아무 일도 안
            // 일어난다" 라서, 띠가 붙어 있는 그림만으로는 확인할 수 없다.
            // 누른 뒤의 화면을 찍어야 글자가 실제로 바뀌는 것이 보인다 —
            // 원격 세션에서 이걸 확인할 수 있는 유일한 길이다.
            guard ProcessInfo.processInfo.arguments.contains("-tapMoneyMultiply") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            // **친 글자 위에서 누른다** (175번). 저장된 값이 아니라 지금 칸에 있는
            // `125` 가 곱해져야 한다. 이 갈고리가 없으면 CI 는 저장값 × 만을 찍어
            // 버그가 있어도 그럴듯해 보인다.
            if ProcessInfo.processInfo.arguments.contains("-typeMoneyDraft") { draft = "125" }
            MoneyKeyboard.shared.active?.multiply(10_000)
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
                // **띠는 화면이 그린다** (152번 3-1). 키보드 툴바는 iOS 가 얹어
                // 주는 것이라 커서가 옮겨 다니면 떼어지고 글자 크기를 바꿔도
                // 다시 그려지지 않는다 (144번). 커서가 오면 손잡이만 건넨다.
                //
                // **손잡이는 값이 아니라 바인딩을 잡는다** (156번). 예전에는
                // `multiply` 라는 구조체 값의 메서드를 통째로 잡아 둬서, 화면이
                // 다시 그려져도 손잡이는 그때의 사본 그대로였다. `@Binding` 과
                // `@State` 의 투영값은 다시 그려져도 같은 저장소를 가리키므로
                // 이 둘만 잡으면 어긋날 자리가 없다.
                .onChange(of: isFocused, initial: true) { _, focused in
                    if focused {
                        draft = Self.display(minorUnits)
                        MoneyKeyboard.shared.activate(
                            .init(id: fieldID,
                                  multiply: { [value = $minorUnits, text = $draft, note = $note] factor in
                                      Self.multiply(factor, value: value, text: text, note: note)
                                  },
                                  focus: $isFocused)
                        )
                    } else {
                        // **손 뗄 때 한 번 저장한다** (169번 C1). 글자마다 저장하면
                        // 살아 있는 다섯 탭이 글자마다 다시 그렸다. 만 · 억은
                        // 누르는 순간 저장한다 — 그건 한 번의 뜻이다 (156번).
                        commitDraft()
                        draft = nil
                        note = nil
                        MoneyKeyboard.shared.resign(fieldID)
                    }
                }
                .onDisappear {
                    // 커서가 있는 채로 화면이 닫히면 적던 값을 잃지 않게.
                    if isFocused { commitDraft() }
                    MoneyKeyboard.shared.resign(fieldID)
                }
            Text("원")
                .font(.scaled(13))
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

    /// 적어 둔 글자를 모델에 쓴다. 같으면 아무 일도 안 한다.
    private func commitDraft() {
        guard let next = Self.parse(draft) else { return }
        guard minorUnits != next else { return }
        minorUnits = next
    }

    /// 친 글자를 값으로. 커서가 없으면(`nil`) 값이 없다.
    private static func parse(_ draft: String?) -> Int? {
        guard let draft else { return nil }
        let digits = String(draft.filter(\.isNumber).prefix(maxDigits))
        return min(Int(digits) ?? 0, ceiling)
    }

    /// **지금 칸에 있는 값.** 커서가 있으면 친 글자, 없으면 모델. 저장은 손 뗄 때지만
    /// (169번) 읽는 값과 만 · 억은 **지금 것**을 봐야 한다 (175번).
    private var currentValue: Int {
        isFocused ? (Self.parse(draft) ?? minorUnits) : minorUnits
    }

    private static func display(_ minorUnits: Int) -> String {
        minorUnits == 0 ? "" : KoreanAmountFormatter.grouped(minorUnits)
    }

    /// `만` · `억` — 12 → 만 → 120,000.
    ///
    /// **곱셈이 가드보다 먼저 있으면 앱이 죽는다** (156번). 예전에는
    /// `minorUnits * factor` 를 먼저 계산하고 나서 한도를 봤다 — 750억이 든
    /// 칸에서 `억` 을 누르면 `Int` 를 넘겨 그 자리에서 트랩이었다. 넘침을
    /// 물어보고, 넘치거나 한도를 지나면 **한도에서 멈추고 말해 준다.**
    ///
    /// **출발점은 모델이 아니라 친 글자다** (175번). 169번부터 치는 동안은
    /// `draft` 만 움직이고 모델은 손 뗄 때 쓴다. 그런데 여기가 모델을 읽어서,
    /// 1,250,000 이 저장된 칸에 `125` 를 치고 `만` 을 누르면 125만이 아니라
    /// **125억**이 됐다 — 옛 저장값 × 만. 칸에 보이는 글자가 곱해져야 한다.
    @MainActor
    private static func multiply(_ factor: Int,
                                 value: Binding<Int>,
                                 text: Binding<String?>,
                                 note: Binding<String?>) {
        let current = parse(text.wrappedValue) ?? value.wrappedValue
        guard current > 0 else {
            note.wrappedValue = "숫자를 먼저 넣으세요"
            return
        }
        let (next, hitLimit) = SafeMath.multiplyClamping(current, by: factor, limit: ceiling)
        guard next != current else {
            note.wrappedValue = "더 크게는 못 넣습니다"
            return
        }
        value.wrappedValue = next
        // **글자도 함께 민다.** 이것이 156번의 고갱이다 — 모델만 바꾸면
        // 커서가 있는 칸은 옛 글자를 그대로 들고 있다가 되쓴다.
        text.wrappedValue = display(next)
        note.wrappedValue = hitLimit ? "한도까지만 올렸습니다" : nil
    }

    private var text: Binding<String> {
        Binding(
            get: {
                // 커서가 있는 동안에는 `draft` 가 칸의 글자다 (156번).
                if isFocused, let draft { return draft }
                return Self.display(minorUnits)
            },
            set: { input in
                let digits = String(input.filter(\.isNumber).prefix(Self.maxDigits))
                // 자릿수를 잘라도 `Int` 로 못 옮기는 글자가 올 수 있다 (붙여넣기).
                let next = min(Int(digits) ?? 0, Self.ceiling)
                // 커서가 있는 동안은 글자만 움직인다. 저장은 손 뗄 때 (169번).
                draft = Self.display(next)
            }
        )
    }
}
