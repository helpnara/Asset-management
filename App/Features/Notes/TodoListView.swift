import Core
import CoreData
import SwiftUI

/// 유의사항 · 할 일. 1페이지 아래쪽의 `※ 주석` 이 여기로 온다.
///
/// 규칙 점검(자산 진단)이 **숫자로 판정하는 것**이라면, 여기는 **숫자로 판정할 수
/// 없는 것**이다. "연금저축 5월까지 채우기", "전세 만기 전에 알아보기" 같은 것들.
struct TodoListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEdit) private var canEdit
    @Fetched(sort: \TodoItem.sortIndex) private var items: [TodoItem]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
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
                            .font(.scaled(12.5))
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .navigationTitle("유의사항 · 할 일")
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

    /// **보기 전용이면 버튼으로 두지 않는다.** 눌러도 아무 일이 없는 버튼은
    /// 잠긴 화면이 아니라 고장 난 화면으로 읽힌다 — 4차가 피하려는 바로 그것이다.
    private func row(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            if canEdit {
                Button {
                    item.isDone.toggle()
                    item.completedAt = item.isDone ? .now : nil
                    Task { await TodoNotifications.refresh(TodoNotifications.Input(items: items, accounts: allAccounts)) }
                } label: {
                    checkmark(item)
                }
                .buttonStyle(.plain)

                Button {
                    editing = item
                } label: {
                    summary(item)
                }
                .buttonStyle(.plain)
            } else {
                checkmark(item)
                summary(item)
            }

            if item.repeatsYearly {
                StatusBadge(text: "매년")
            }
        }
        .padding(.vertical, 2)
    }

    private func checkmark(_ item: TodoItem) -> some View {
        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            .font(.scaled(18))
            .foregroundStyle(item.isDone ? Color.gain : Color.ruleStrong)
    }

    private func summary(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title.isEmpty ? "이름 없음" : item.title)
                .font(.scaled(13))
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

    private func deadlineText(_ days: Int) -> String {
        if days < 0 { return "\(-days)일 지남" }
        if days == 0 { return "오늘까지" }
        return "\(days)일 남음"
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

                if !isNew {
                    Section {
                        DeleteButton("\(item.title.isEmpty ? "이 할 일" : item.title) 을(를) 삭제할까요?",
                                     consequence: "되돌릴 수 없습니다.") {
                            context.delete(item)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("할 일")
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
