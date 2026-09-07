import SwiftData
import SwiftUI

/// 운용 원칙 — 1페이지 D블록을 채우는 곳.
///
/// 원칙은 사람이 쓰는 문장이라 앱이 지어낼 수 없다. 담을 곳만 만든다
/// (docs/08-feedback.md 10번).
///
/// 자산 진단(여섯 가지)과는 다른 것이다. 진단은 계산으로 판정할 수 있는 것을
/// 보고, 여기는 **"하락장에도 멈추지 않는다"** 처럼 계산으로는 못 보는 것을
/// 글로 남긴다.
struct PrincipleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Principle.order) private var principles: [Principle]
    @State private var pendingDelete: IndexSet?

    var body: some View {
        List {
            ForEach(principles) { principle in
                @Bindable var principle = principle
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(principle.order).")
                            .font(.figure(13, weight: .semibold))
                            .foregroundStyle(Color.faint)
                        TextField("한 줄 제목", text: $principle.title)
                            .font(.system(size: 14, weight: .medium))
                    }
                    TextField("부연 설명", text: $principle.detail, axis: .vertical)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bodyText)
                        .lineLimit(1...4)
                    TextField("점검 주기 (분기 1회 …)", text: $principle.reviewNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.muted)
                }
                .padding(.vertical, 2)
            }
            .onDelete { pendingDelete = $0 }
            .onMove(perform: move)

            Button {
                add()
            } label: {
                Label("원칙 추가", systemImage: "plus")
                    .font(.system(size: 13))
            }
        }
        .confirmsDelete($pendingDelete, title: "이 원칙을 삭제할까요?",
                        message: "1페이지 계획서의 원칙 칸에서도 사라집니다. 되돌릴 수 없습니다.",
                        perform: delete)
        .navigationTitle("운용 원칙")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .overlay {
            if principles.isEmpty {
                VStack(spacing: 10) {
                    Text("아직 적은 원칙이 없습니다")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("\"동결 종목에는 신규 자금을 넣지 않는다\" 처럼\n지키기로 한 것을 적어 두면 1페이지에 함께 나갑니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(30)
            }
        }
    }

    private func add() {
        context.insert(Principle(order: principles.count + 1))
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(principles[index]) }
        renumber()
    }

    private func move(_ offsets: IndexSet, to destination: Int) {
        var items = principles
        items.move(fromOffsets: offsets, toOffset: destination)
        for (index, item) in items.enumerated() { item.order = index + 1 }
    }

    /// 번호는 1페이지에 그대로 찍히므로 빈 번호를 남기지 않는다.
    private func renumber() {
        for (index, item) in principles.enumerated() where item.order != index + 1 {
            item.order = index + 1
        }
    }
}
