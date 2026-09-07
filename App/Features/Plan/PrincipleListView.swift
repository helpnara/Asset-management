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
    // 원칙은 1페이지에 실려 가족 밖으로도 나가는 문서다 — 관리자만 고친다.
    @Environment(\.canManageHousehold) private var canManageHousehold
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
                // 줄 자체가 입력칸이라 여기도 잠가야 한다.
                .disabled(!canManageHousehold)
            }
            .onDelete(perform: canManageHousehold
                      ? { (offsets: IndexSet) in pendingDelete = offsets } : nil)
            .onMove(perform: canManageHousehold ? move : nil)

            if canManageHousehold {
                Button {
                    add()
                } label: {
                    Label("원칙 추가", systemImage: "plus")
                        .font(.system(size: 13))
                }
            }

            // 기본값을 첫 실행 때 심지 않는 이유는 `DefaultPrinciples` 에 적어 두었다.
            // 이미 쓰고 있는 사람에게도 와야 해서 버튼으로 둔다.
            if !missingDefaults.isEmpty && canManageHousehold {
                Section {
                    Button {
                        addDefaults()
                    } label: {
                        Label("기본 원칙 넣기 (\(missingDefaults.count)개)",
                              systemImage: "text.badge.plus")
                            .font(.system(size: 13))
                    }
                } footer: {
                    Text("투자 원칙 열여섯 개를 그대로 넣습니다. 넣은 뒤에 고치고 지울 수 있고, 이미 적어 둔 것과 같은 문장은 건너뜁니다.")
                }
            }
        }
        .confirmsDelete($pendingDelete, title: "이 원칙을 삭제할까요?",
                        message: "1페이지 계획서의 원칙 칸에서도 사라집니다. 되돌릴 수 없습니다.",
                        perform: delete)
        .navigationTitle("운용 원칙")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if canManageHousehold { EditButton() } }
        .overlay {
            if principles.isEmpty {
                VStack(spacing: 10) {
                    Text("아직 적은 원칙이 없습니다")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("\"동결 종목에는 신규 자금을 넣지 않는다\" 처럼\n지키기로 한 것을 적어 두면 1페이지에 함께 나갑니다.\n\n위의 **기본 원칙 넣기** 를 누르면 열여섯 개로 시작할 수 있습니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(30)
                // 비어 있을 때 뜨는 안내가 아래 버튼을 가로채면 안 된다.
                .allowsHitTesting(false)
            }
        }
    }

    private func add() {
        context.insert(Principle(order: principles.count + 1))
    }

    /// 아직 없는 기본 원칙들. 전부 있으면 버튼 자체가 사라진다.
    private var missingDefaults: [String] {
        DefaultPrinciples.missing(from: principles)
    }

    /// 있는 것 뒤에 이어 붙인다. 적어 둔 순서를 흔들지 않는다.
    private func addDefaults() {
        var order = principles.count
        for title in missingDefaults {
            order += 1
            context.insert(Principle(order: order, title: title))
        }
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
