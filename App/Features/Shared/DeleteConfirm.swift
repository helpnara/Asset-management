import SwiftUI

/// 삭제 전에 한 번 더 묻는다 (docs/08-feedback.md 16번).
///
/// **왜 필요한가.** 편집 시트의 `삭제` 가 `topBarLeading` 에 있는데, 그 자리는
/// 보통 화면에서 **뒤로 가기**가 있는 자리다. 손이 기억하는 위치라 무심코
/// 누르게 된다. 게다가 이 앱이 지우는 것은 되돌릴 방법이 없다 — 구성원을
/// 지우면 그 아래 계좌와 종목이 전부 함께 사라진다(cascade).
///
/// 그래서 이 앱의 삭제는 **전부** 이 부품을 거친다. 확인 문구에 무엇이 함께
/// 사라지는지 적는 것이 이 부품의 핵심이다 — "정말 삭제할까요?" 만으로는
/// 계좌 하나를 지우는 줄 알고 종목 열 개를 잃는다.
struct DeleteButton<Label: View>: View {
    /// 확인 창의 제목. 무엇을 지우는지 이름을 적는다.
    let title: String
    /// 무엇이 함께 사라지는지. 딸린 것이 없으면 nil.
    var consequence: String?
    let action: () -> Void
    @ViewBuilder var label: Label

    @State private var isConfirming = false

    var body: some View {
        Button(role: .destructive) { isConfirming = true } label: { label }
            .confirmationDialog(title, isPresented: $isConfirming, titleVisibility: .visible) {
                Button("삭제", role: .destructive, action: action)
                Button("취소", role: .cancel) {}
            } message: {
                if let consequence { Text(consequence) }
            }
    }
}

extension DeleteButton where Label == Text {
    /// 편집 시트 툴바에서 쓰는 기본 모양.
    init(_ title: String, consequence: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, consequence: consequence, action: action) { Text("삭제") }
    }
}

/// **밀어서 지우기 — 줄은 확인 뒤에만 사라진다** (180번).
///
/// `.onDelete` 를 쓰면 안 된다. 그것은 사용자가 밀어 `삭제` 를 누르는 순간
/// **목록이 먼저 줄을 걷어내고** 자료가 따라오기를 기다린다. 우리는 확인 창을
/// 띄우느라 그 자리에서 지우지 않으므로, **걷혔던 줄이 도로 들어왔다가**
/// 확인 뒤에 다시 나간다 — 기기에서 "뭔가 생겼다 없어진다" 로 보이던 것이
/// 이것이다 (빌드 102 · 103 에서 두 번 딴 데를 고쳤다).
///
/// `swipeActions` 의 버튼은 줄을 건드리지 않는다. 누르면 우리 확인 창이 뜨고,
/// `삭제` 를 눌러 자료가 바뀔 때 비로소 줄이 한 번 나간다.
///
/// ```swift
/// ForEach(items) { item in
///     row(item).swipeToDelete(title: "이 종목을 삭제할까요?") { delete(item) }
/// }
/// ```
extension View {
    func swipeToDelete(title: String,
                       message: String? = nil,
                       enabled: Bool = true,
                       perform: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(title: title, message: message,
                               enabled: enabled, perform: perform))
    }
}

private struct SwipeToDelete: ViewModifier {
    let title: String
    let message: String?
    let enabled: Bool
    let perform: () -> Void
    @State private var isConfirming = false

    func body(content: Content) -> some View {
        content
            // 전부 밀어도 바로 지워지지 않게 한다 — 되돌릴 수 없는 일이다 (16번).
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if enabled {
                    Button("삭제", role: .destructive) { isConfirming = true }
                }
            }
            .confirmationDialog(title, isPresented: $isConfirming, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { withAnimation { perform() } }
                Button("취소", role: .cancel) {}
            } message: {
                if let message { Text(message) }
            }
    }
}
