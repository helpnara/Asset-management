import Core
import CoreData
import SwiftUI

/// **챙길 것** (172번 — 예전 이름 `유의사항 · 할 일`). 1페이지 아래쪽의 `※ 주석` 이
/// 여기로 온다.
///
/// 규칙 점검(자산 진단)이 **숫자로 판정하는 것**이라면, 여기는 **숫자로 판정할 수
/// 없는 것**이다. "연금저축 5월까지 채우기", "전세 만기 전에 알아보기" 같은 것들.
///
/// **원칙과 갈라 선다.** 원칙(운용 원칙)은 지킬 것이고 날짜가 없다. 여기는
/// 챙길 것이고 언제까지가 있다. 날짜 없는 메모가 사실은 원칙이면 밀어서
/// 원칙으로 보낸다. 목록은 분류가 아니라 **시간으로** 묶는다 — 지난 것 ·
/// 30일 안 · 그 뒤 · 날짜 없음.
struct TodoListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEdit) private var canEdit
    @Fetched(sort: \TodoItem.sortIndex) private var items: [TodoItem]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched(sort: \Principle.order) private var principles: [Principle]
    @State private var editing: TodoItem?
    /// 방금 만든 것의 id — 편집 시트의 `취소` 가 지운다 (104번).
    @State private var newIDs: Set<UUID> = []
    @State private var showsDone = false

    /// 만기 알림을 다시 걸 때 함께 넘긴다. 안 넘기면 할 일을 하나 고칠 때마다
    /// 걸어 둔 만기 알림이 조용히 지워진다.
    private var allAccounts: [Account] { members.flatMap(\.sortedAccounts) }

    private var open: [TodoItem] { items.filter { !$0.isDone } }
    private var done: [TodoItem] { items.filter(\.isDone) }

    var body: some View {
        List {
            // 만기 줄이 떠 있는데 "아직 적어 둔 것이 없습니다" 가 함께 나오면
            // 화면이 두 말을 한다 (docs/08-feedback.md 45번).
            if open.isEmpty && done.isEmpty && upcomingMaturities.isEmpty {
                Section {
                    Text(canEdit
                         ? "아직 적어 둔 것이 없습니다. 오른쪽 위 + 로 추가하세요.\n\"연금저축 5월까지 채우기\" 처럼 숫자로 판정할 수 없는 것들을 여기 둡니다."
                         : "아직 적어 둔 것이 없습니다. 관리자가 적으면 여기에 보입니다.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            // **만기는 적어 둔 할 일이 아니라 계좌에서 자동으로 온다**
            // (docs/08-feedback.md 28번). `TodoItem` 을 만들어 넣지 않는 이유는
            // 앱이 켜질 때마다 같은 것을 또 만들게 되고, 사용자가 지워도 다시
            // 살아나기 때문이다. 계좌의 날짜를 그대로 읽어 보여 준다.
            if !upcomingMaturities.isEmpty {
                Section {
                    ForEach(upcomingMaturities, id: \.id) { account in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.scaled(13))
                                .foregroundStyle(Color.loss)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(maturityTitle(account))
                                    .font(.scaled(13.5, weight: .medium))
                                    .foregroundStyle(Color.ink)
                                Text(maturityDetail(account))
                                    .font(.scaled(11.5))
                                    .foregroundStyle(Color.muted)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("다가오는 만기")
                } footer: {
                    Text("계좌에 적어 둔 만기일이 90일 안으로 들어오면 여기 뜹니다. 계좌 화면에서 날짜를 고칠 수 있습니다.")
                }
            }

            ForEach(TodoItem.Bucket.allCases) { bucket in
                let group = open.filter { $0.bucket == bucket }
                    .sorted { ($0.dueDate ?? .distantFuture, $0.sortIndex) < ($1.dueDate ?? .distantFuture, $1.sortIndex) }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { item in
                            todoRow(item)
                                // 날짜 없는 것이 사실은 원칙이면 그리로 (172번).
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if canEdit && bucket == .undated {
                                        Button { moveToPrinciple(item) } label: {
                                            Label("원칙으로", systemImage: "list.number")
                                        }
                                        .tint(Color.gain)
                                    }
                                }
                        }
                    } header: {
                        Text(bucket.rawValue)
                    } footer: {
                        if bucket == .undated {
                            Text("날짜가 없으면 알림을 걸지 않습니다. 지킬 원칙이면 오른쪽으로 밀어 운용 원칙으로 옮기세요.")
                        } else if bucket == .soon {
                            Text("날짜 30일 전과 당일 아침 9시에 알립니다. 현황판에도 뜹니다.")
                        }
                    }
                }
            }

            if !done.isEmpty {
                Section {
                    // 완료 항목은 접어 둔다. 다 한 일이 목록의 절반을 차지하면
                    // 남은 일이 안 보인다.
                    DisclosureGroup(isExpanded: $showsDone) {
                        ForEach(done) { todoRow($0) }
                    } label: {
                        Text("완료 \(done.count)건")
                            .font(.scaled(12.5))
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .navigationTitle("챙길 것")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canEdit {
                    Button {
                        let item = TodoItem(context: context, sortIndex: items.count)
                        newIDs.insert(item.id)
                        editing = item
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing, onDismiss: { newIDs.removeAll() }) {
            TodoEditView(item: $0, isNew: newIDs.contains($0.id))
        }
    }

    /// 90일 안으로 들어온 만기. 지난 것도 한 달까지는 남긴다 — 연장했는지
    /// 확인하지 않은 채 사라지면 그게 더 위험하다.
    private var upcomingMaturities: [Account] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return members
            .flatMap(\.sortedAccounts)
            .filter { !$0.isArchived }
            .filter { account in
                guard let days = daysUntilMaturity(account) else { return false }
                return days >= -30 && days <= 90
            }
            .sorted { ($0.maturesOn ?? today) < ($1.maturesOn ?? today) }
    }

    private func daysUntilMaturity(_ account: Account) -> Int? {
        guard let date = account.maturesOn else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: .now),
                                       to: calendar.startOfDay(for: date)).day
    }

    private func maturityTitle(_ account: Account) -> String {
        let owner = account.owner?.name ?? ""
        let name = account.weightLabel
        return owner.isEmpty ? name : "\(owner) · \(name)"
    }

    private func maturityDetail(_ account: Account) -> String {
        guard let date = account.maturesOn, let days = daysUntilMaturity(account) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        let day = formatter.string(from: date)
        if days < 0 { return "\(day) — 만기가 \(-days)일 지났습니다" }
        if days == 0 { return "\(day) — 오늘이 만기입니다" }
        return "\(day) — \(days)일 남았습니다"
    }

    /// 날짜 없는 메모를 운용 원칙으로 보낸다. 글은 그대로, 여기서는 빠진다.
    private func moveToPrinciple(_ item: TodoItem) {
        let order = (principles.map(\.order).max() ?? 0) + 1
        _ = Principle(context: context, order: order, title: item.title, detail: item.detail)
        ChangeLogger.record(.other, subject: "원칙으로 옮김", summary: item.title, in: context)
        context.delete(item)
    }

    private func todoRow(_ item: TodoItem) -> some View {
        TodoRow(item: item, canEdit: canEdit,
                onToggle: {
                    item.isDone.toggle()
                    item.completedAt = item.isDone ? .now : nil
                    Task { await TodoNotifications.refresh(TodoNotifications.Input(items: items, accounts: allAccounts)) }
                },
                onEdit: { editing = item })
    }
}

/// 한 줄 (150번). 관리 객체를 그리는 줄은 그 객체를 지켜본다 —
/// 이유는 `DiaryRow` 에 적어 두었다.
///
/// **보기 전용이면 버튼으로 두지 않는다.** 눌러도 아무 일이 없는 버튼은
/// 잠긴 화면이 아니라 고장 난 화면으로 읽힌다 — 4차가 피하려는 바로 그것이다.
private struct TodoRow: View {
    @ObservedObject var item: TodoItem
    var canEdit: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            if canEdit {
                Button(action: onToggle) { checkmark }
                    .buttonStyle(.plain)
                Button(action: onEdit) { summary }
                    .buttonStyle(.plain)
            } else {
                checkmark
                summary
            }

            if item.repeatsYearly {
                StatusBadge(text: "매년")
            }
        }
        .padding(.vertical, 2)
    }

    private var checkmark: some View {
        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            .font(.scaled(18))
            .foregroundStyle(item.isDone ? Color.gain : Color.ruleStrong)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title.isEmpty ? "이름 없음" : item.title)
                .font(.scaled(13))
                .foregroundStyle(item.isDone ? Color.faint : Color.ink)
                .strikethrough(item.isDone, color: Color.faint)
                .multilineTextAlignment(.leading)
            // 분류는 꼬리표로만 (172번). 묶음은 시간이 한다.
            if item.category.showsTag || (item.daysRemaining != nil && !item.isDone) {
                HStack(spacing: 6) {
                    if item.category.showsTag {
                        StatusBadge(text: item.category.label)
                    }
                    if let days = item.daysRemaining, !item.isDone {
                        Text(item.dueText)
                            .font(.figure(10.5))
                            .foregroundStyle(days < 0 ? Color.loss
                                             : (days <= 14 ? Color.dad : Color.faint))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodoEditView: View {
    @ObservedObject var item: TodoItem
    /// 방금 만든 것인가 — 취소하면 지운다 (104번).
    var isNew = false
    @State private var snapshot: EditSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \TodoItem.sortIndex) private var items: [TodoItem]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    @State private var hasDue: Bool

    /// 알림을 통째로 다시 걸므로 만기도 함께 넘겨야 한다.
    private var allAccounts: [Account] { members.flatMap(\.sortedAccounts) }

    init(item: TodoItem, isNew: Bool = false) {
        self.item = item
        self.isNew = isNew
        _hasDue = State(initialValue: item.dueDate != nil)
    }

    var body: some View {
        // 지운 객체를 시트가 내려가며 한 번 더 그리다 죽지 않게 (189번).
        if item.isGone {
            Color.clear
        } else {
            editor
        }
    }

    @ViewBuilder private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("챙길 것 (연금저축 5월까지 채우기 …)", text: $item.title)
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
                         ? "날짜 30일 전과 당일 아침 9시에 알립니다. 주간 점검 알림과 따로 걸립니다."
                         : "날짜 없는 메모입니다. 알림을 걸지 않습니다. 지킬 원칙이라면 운용 원칙에 두세요.")
                }

                Section("메모") {
                    TextField("자세한 내용", text: $item.detail, axis: .vertical)
                        .lineLimit(1...5)
                }

                if !isNew {
                    Section {
                        DeleteButton("\(item.title.isEmpty ? "이 항목" : item.title) 을(를) 삭제할까요?",
                                     consequence: "되돌릴 수 없습니다.") {
                            context.delete(item)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("챙길 것")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if snapshot == nil { snapshot = EditSnapshot(of: item) } }
            .onChange(of: hasDue) { _, on in
                item.dueDate = on ? (item.dueDate ?? .now) : nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onDisappear {
                let input = TodoNotifications.Input(items: items, accounts: allAccounts)
                Task { await TodoNotifications.refresh(input) }
            }
        }
    }

    private var dueDate: Binding<Date> {
        Binding(get: { item.dueDate ?? .now }, set: { item.dueDate = $0 })
    }

    private func cancel() {
        if isNew { context.delete(item) } else { snapshot?.restore(to: item) }
        dismiss()
    }
}
