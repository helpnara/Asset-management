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
/// 띄우느라 그 자리에서 지우지 않으므로, 걷혔던 줄이 도로 들어왔다가 확인 뒤에
/// 다시 나간다 — "뭔가 생겼다 없어진다" 가 그것이었다.
///
/// **확인 창은 줄이 아니라 화면이 들고 있는다** (181번). 줄마다 `@State` 와
/// 확인 창을 들려 줬더니 미는 사이에 줄이 다시 그려지면 그 상태가 날아가
/// **창이 떴다 사라졌다.**
///
/// **그런데 화면의 `@State` 로 들면 목록 전체가 다시 그려진다** (182번).
/// 미는 버튼을 누르는 순간 값이 바뀌고, 화면 몸체가 다시 돌아 목록에 새 나무를
/// 건넨다 — 그때 밀린 줄은 아직 닫히는 중이라, 그 **아래 줄이 사라졌다
/// 돌아오는** 것이 보였다. 그래서 지울 대상은 화면이 **읽지 않는 그릇**에
/// 담고(`PendingDelete`), 확인 창을 그리는 작은 뷰만 그 값을 읽는다. 값이 바뀌어도
/// 다시 그려지는 것은 그 작은 뷰뿐이다.
///
/// ```swift
/// @State private var pendingDelete = PendingDelete<Item>()
/// ...
/// row(item).swipeDelete { pendingDelete.item = item }
/// ...
/// .confirmsDelete(pendingDelete, title: "이것을 삭제할까요?") { delete($0) }
/// ```
@Observable
@MainActor
final class PendingDelete<Item> {
    var item: Item?
    init() {}
}

extension View {
    /// 줄에 붙이는 밀기 버튼. **줄 자체에 붙인다** — `Group` 으로 감싸고 그 위에
    /// 붙이면 미는 동작이 조용히 사라진다 (181번).
    func swipeDelete(_ action: @escaping () -> Void) -> some View {
        // 전부 밀어도 바로 지워지지 않게 한다 — 되돌릴 수 없는 일이다 (16번).
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // **색을 못 박는다** (181번). 앱 전체의 `tint` 가 `Color.ink`
            // (어두운 화면에서는 흰색)이고 미는 버튼은 그 색을 바탕으로 쓴다 —
            // 흰 바탕에 흰 글씨라 `삭제` 가 안 보였다.
            Button("삭제", role: .destructive, action: action)
                .tint(Color.loss)
        }
    }

    /// 화면에 한 장. 그릇에 담긴 것이 있으면 확인 창을 띄운다. 부르는 화면은
    /// 그릇을 만들어 건네기만 하고 **안을 읽지 않는다** (182번).
    func confirmsDelete<Item>(_ pending: PendingDelete<Item>,
                              title: String,
                              message: @escaping (Item) -> String = { _ in "되돌릴 수 없습니다." },
                              perform: @escaping (Item) -> Void) -> some View {
        background {
            DeleteDialogHost(pending: pending, title: title, message: message, perform: perform)
        }
    }
}

/// 확인 창 하나만 그리는 작은 뷰. 그릇의 값을 읽는 유일한 자리다.
private struct DeleteDialogHost<Item>: View {
    let pending: PendingDelete<Item>
    let title: String
    let message: (Item) -> String
    let perform: (Item) -> Void

    var body: some View {
        Color.clear
            .confirmationDialog(title,
                                isPresented: Binding(get: { pending.item != nil },
                                                     set: { if !$0 { pending.item = nil } }),
                                titleVisibility: .visible,
                                presenting: pending.item) { item in
                Button("삭제", role: .destructive) {
                    withAnimation { perform(item) }
                    pending.item = nil
                }
                Button("취소", role: .cancel) { pending.item = nil }
            } message: { item in
                Text(message(item))
            }
    }
}
