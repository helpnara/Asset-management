import CoreData
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
    @Environment(\.managedObjectContext) private var context
    // 원칙은 1페이지에 실려 가족 밖으로도 나가는 문서다 — 관리자만 고친다.
    @Environment(\.canManageHousehold) private var canManageHousehold
    @Fetched(sort: \Principle.order) private var principles: [Principle]
    /// 고치는 것은 시트에서 한다 (152번 2-1). 목록에 입력칸을 늘어놓으면
    /// **목록이 아니라 편집 폼**으로 보이고, 적지 않은 `부연 설명` ·
    /// `점검 주기` 빈 칸이 열여섯 줄 내내 따라다녀 길이가 두 배가 된다.
    /// 마일스톤 · 할 일 · 일기가 전부 "누르면 시트" 라 꼴도 여기만 달랐다.
    @State private var editing: Principle?
    /// 방금 만든 것 — 시트에서 `취소` 하면 지운다 (104번과 같은 꼴).
    @State private var newIDs: Set<UUID> = []

    var body: some View {
        list
            .navigationTitle("운용 원칙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay { emptyNote }
            .sheet(item: $editing, onDismiss: { newIDs.removeAll() }) { principle in
                PrincipleEditView(principle: principle,
                                  isNew: newIDs.contains(principle.id),
                                  onDelete: { remove(principle) })
            }
    }

    /// **툴바를 따로 뽑는다.** `.toolbar { ... }` 는 `ViewBuilder` 판과
    /// `ToolbarContentBuilder` 판이 둘 다 있어서, 안이 조금만 복잡해지면
    /// 어느 쪽인지 못 골라 `ambiguous use of 'toolbar(content:)'` 로 막힌다.
    /// 반환 타입을 `some ToolbarContent` 로 적어 두면 고를 것이 없다.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if canManageHousehold { EditButton() }
        }
    }

    private var list: some View {
        List {
            ForEach(principles) { principle in
                Group {
                    // 보기 전용이면 버튼으로 두지 않는다 — 눌러도 아무 일이 없는
                    // 버튼은 잠긴 화면이 아니라 고장 난 화면으로 읽힌다.
                    if canManageHousehold {
                        Button { editing = principle } label: { PrincipleRow(principle: principle) }
                            .buttonStyle(.plain)
                    } else {
                        PrincipleRow(principle: principle)
                    }
                }
                // 밀어 지우기는 줄마다 (180번).
                .swipeToDelete(title: "이 원칙을 삭제할까요?",
                               message: "1페이지 계획서의 원칙 칸에서도 사라집니다. 되돌릴 수 없습니다.",
                               enabled: canManageHousehold) { remove(principle) }
            }
            .onMove(perform: canManageHousehold
                    ? { (offsets: IndexSet, destination: Int) in
                        move(offsets, to: destination)
                    } : nil)

            if canManageHousehold {
                Button {
                    add()
                } label: {
                    Label("원칙 추가", systemImage: "plus")
                        .font(.scaled(13))
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
                            .font(.scaled(13))
                    }
                } footer: {
                    Text("투자 원칙 열여섯 개를 그대로 넣습니다. 넣은 뒤에 고치고 지울 수 있고, 이미 적어 둔 것과 같은 문장은 건너뜁니다.")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyNote: some View {
        if principles.isEmpty {
            VStack(spacing: 10) {
                Text("아직 적은 원칙이 없습니다")
                    .font(.scaled(14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("\"동결 종목에는 신규 자금을 넣지 않는다\" 처럼\n지키기로 한 것을 적어 두면 1페이지에 함께 나갑니다.\n\n위의 기본 원칙 넣기 를 누르면 열여섯 개로 시작할 수 있습니다.")
                    .font(.scaled(12))
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(30)
            // 비어 있을 때 뜨는 안내가 아래 버튼을 가로채면 안 된다.
            .allowsHitTesting(false)
        }
    }

    /// 만들자마자 시트를 연다 — 빈 줄만 하나 생기고 어디에 적는지 모르는 것이
    /// 이 화면의 원래 문제였다.
    private func add() {
        let principle = Principle(context: context, order: principles.count + 1)
        newIDs.insert(principle.id)
        editing = principle
    }

    /// 시트 안에서 지울 때. 번호를 다시 매긴다.
    private func remove(_ principle: Principle) {
        context.delete(principle)
        renumber()
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
            _ = Principle(context: context, order: order, title: title)
        }
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

/// 한 줄. 번호 · 제목, 적어 둔 것이 있으면 부연과 점검 주기까지 **작게** 곁들인다.
/// 적지 않은 칸은 줄에 자리를 차지하지 않는다 (152번 2-1).
///
/// 관리 객체를 그리는 줄이라 `@ObservedObject` 로 받는다 — 시트에서 고치고
/// 닫았을 때 목록이 그대로이던 것(150번)과 같은 이유다.
private struct PrincipleRow: View {
    @ObservedObject var principle: Principle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(principle.order).")
                .font(.figure(13, weight: .semibold))
                .foregroundStyle(Color.faint)
            VStack(alignment: .leading, spacing: 3) {
                Text(principle.title.isEmpty ? "이름 없음" : principle.title)
                    .font(.scaled(14, weight: .medium))
                    .foregroundStyle(principle.title.isEmpty ? Color.faint : Color.ink)
                    .multilineTextAlignment(.leading)
                if !principle.detail.isEmpty {
                    Text(principle.detail)
                        .font(.scaled(11.5))
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                if !principle.reviewNote.isEmpty {
                    Text(principle.reviewNote)
                        .font(.scaled(10.5))
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// 원칙 하나를 고치는 시트 (152번 2-1). 다른 목록(마일스톤 · 할 일)과 같은 꼴이다.
struct PrincipleEditView: View {
    @ObservedObject var principle: Principle
    /// 방금 만든 것인가 — 취소하면 지운다 (104번).
    var isNew = false
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var snapshot: EditSnapshot?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("한 줄 제목 (하락을 두려워하지 마라 …)", text: $principle.title,
                              axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text("1페이지에 이 문장이 그대로 실립니다. 앱이 문장을 다듬지 않습니다.")
                }

                Section("부연") {
                    TextField("자세한 내용", text: $principle.detail, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    TextField("점검 주기 (분기 1회 …)", text: $principle.reviewNote)
                } header: {
                    Text("점검 주기")
                } footer: {
                    Text("언제 돌아볼지를 스스로 적어 두는 칸입니다. 앱이 이 주기로 부르지는 않습니다.")
                }

                if !isNew {
                    Section {
                        DeleteButton("이 원칙을 삭제할까요?",
                                     consequence: "1페이지 계획서의 원칙 칸에서도 사라집니다. 되돌릴 수 없습니다.") {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "원칙 추가" : "운용 원칙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if isNew { context.delete(principle) } else { snapshot?.restore(to: principle) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { if snapshot == nil { snapshot = EditSnapshot(of: principle) } }
        }
    }
}
