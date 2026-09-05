import Core
import SwiftData
import SwiftUI

/// 유의사항 · 할 일. 1페이지 아래쪽의 `※ 주석` 이 여기로 온다.
///
/// 규칙 점검(자산 진단)이 **숫자로 판정하는 것**이라면, 여기는 **숫자로 판정할 수
/// 없는 것**이다. "연금저축 5월까지 채우기", "전세 만기 전에 알아보기" 같은 것들.
struct TodoListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.sortIndex) private var items: [TodoItem]
    @State private var editing: TodoItem?
    @State private var showsDone = false

    private var open: [TodoItem] { items.filter { !$0.isDone } }
    private var done: [TodoItem] { items.filter(\.isDone) }

    var body: some View {
        List {
            if open.isEmpty && done.isEmpty {
                Section {
                    Text("아직 적어 둔 것이 없습니다. 오른쪽 위 + 로 추가하세요.\n\"연금저축 5월까지 채우기\" 처럼 숫자로 판정할 수 없는 것들을 여기 둡니다.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            ForEach(TodoCategory.allCases) { category in
                let group = open.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category.label) {
                        ForEach(group) { row($0) }
                    }
                }
            }

            if !done.isEmpty {
                Section {
                    // 완료 항목은 접어 둔다. 다 한 일이 목록의 절반을 차지하면
                    // 남은 일이 안 보인다.
                    DisclosureGroup(isExpanded: $showsDone) {
                        ForEach(done) { row($0) }
                    } label: {
                        Text("완료 \(done.count)건")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .navigationTitle("유의사항 · 할 일")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let item = TodoItem(sortIndex: items.count)
                    context.insert(item)
                    editing = item
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { TodoEditView(item: $0) }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                item.isDone.toggle()
                item.completedAt = item.isDone ? .now : nil
                Task { await TodoNotifications.refresh(TodoNotifications.Input(items: items)) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isDone ? Color.gain : Color.ruleStrong)
            }
            .buttonStyle(.plain)

            Button {
                editing = item
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "이름 없음" : item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(item.isDone ? Color.faint : Color.ink)
                        .strikethrough(item.isDone, color: Color.faint)
                        .multilineTextAlignment(.leading)
                    if let days = item.daysRemaining, !item.isDone {
                        Text(deadlineText(days))
                            .font(.figure(10.5))
                            .foregroundStyle(days < 0 ? Color.loss
                                             : (days <= 14 ? Color.dad : Color.faint))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if item.repeatsYearly {
                StatusBadge(text: "매년")
            }
        }
        .padding(.vertical, 2)
    }

    private func deadlineText(_ days: Int) -> String {
        if days < 0 { return "\(-days)일 지남" }
        if days == 0 { return "오늘까지" }
        return "\(days)일 남음"
    }
}

struct TodoEditView: View {
    @Bindable var item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.sortIndex) private var items: [TodoItem]

    @State private var hasDue: Bool

    init(item: TodoItem) {
        self.item = item
        _hasDue = State(initialValue: item.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("할 일 (연금저축 5월까지 채우기 …)", text: $item.title)
                    Picker("분류", selection: $item.category) {
                        ForEach(TodoCategory.allCases) {
                            Label($0.label, systemImage: $0.symbol).tag($0)
                        }
                    }
                }

                Section {
                    Toggle("기한이 있다", isOn: $hasDue)
                    if hasDue {
                        DatePicker("기한", selection: dueDate, displayedComponents: .date)
                        Toggle("해마다 되돌아온다", isOn: $item.repeatsYearly)
                    }
                } footer: {
                    Text(hasDue
                         ? "기한 당일 아침 9시에 한 번 알립니다. 주간 점검 알림과 따로 걸립니다."
                         : "기한 없는 메모입니다. 알림을 걸지 않습니다.")
                }

                Section("메모") {
                    TextField("자세한 내용", text: $item.detail, axis: .vertical)
                        .lineLimit(1...5)
                }
            }
            .navigationTitle("할 일")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: hasDue) { _, on in
                item.dueDate = on ? (item.dueDate ?? .now) : nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("삭제", role: .destructive) {
                        context.delete(item)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onDisappear {
                let input = TodoNotifications.Input(items: items)
                Task { await TodoNotifications.refresh(input) }
            }
        }
    }

    private var dueDate: Binding<Date> {
        Binding(get: { item.dueDate ?? .now }, set: { item.dueDate = $0 })
    }
}
