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

/// 목록에서 밀어 지우기(`onDelete`) 를 확인 뒤로 미룬다.
///
/// `onDelete` 는 확인 창을 띄울 자리가 없다. 지울 위치를 붙잡아 두었다가
/// 사용자가 확인하면 그때 실제로 지운다.
///
/// ```swift
/// @State private var pendingDelete: IndexSet?
/// ...
/// .onDelete { pendingDelete = $0 }
/// .confirmsDelete($pendingDelete, title: "지난 기록을 삭제할까요?") { offsets in ... }
/// ```
extension View {
    func confirmsDelete(_ pending: Binding<IndexSet?>,
                        title: String,
                        message: String? = nil,
                        perform: @escaping (IndexSet) -> Void) -> some View {
        confirmationDialog(title, isPresented: Binding(
            get: { pending.wrappedValue != nil },
            set: { if !$0 { pending.wrappedValue = nil } }
        ), titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let offsets = pending.wrappedValue { perform(offsets) }
                pending.wrappedValue = nil
            }
            Button("취소", role: .cancel) { pending.wrappedValue = nil }
        } message: {
            if let message { Text(message) }
        }
    }
}
