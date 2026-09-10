import CoreData
import SwiftUI

/// **지난 일기.** 날짜 내림차순. 항목을 누르면 고치고, 밀어서 지운다.
///
/// 일기는 이 사람의 것이라 `\.canEdit` 을 보지 않는다 (`DiaryCard` 참고).
struct DiaryListView: View {
    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var entries: [DiaryEntry]
    @State private var editing: DiaryEntry?

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("아직 적은 날이 없습니다. 현황판 맨 위 칸에 오늘 한 줄을 적으면 여기 쌓입니다.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                }
            }
            ForEach(entries) { entry in
                Button {
                    editing = entry
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DiaryCard.dayText(entry.day))
                            .font(.figure(11, weight: .medium))
                            .foregroundStyle(Color.muted)
                        row("목표", entry.goal)
                        row("실적", entry.result)
                        row("감사", entry.gratitude)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(entries[index]) }
            }
        }
        .navigationTitle("목 · 실 · 감")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in DiaryEditView(entry: entry) }
    }

    @ViewBuilder
    private func row(_ label: String, _ text: String) -> some View {
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .frame(width: 26, alignment: .leading)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}

struct DiaryEditView: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var dayTaken = false
    /// 되돌리는 중이라는 표시. 되돌리는 대입도 `onChange` 를 다시 울리므로,
    /// 그 한 번은 검사하지 않아야 안내 문구가 남는다.
    @State private var reverting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("날짜", selection: $entry.day, displayedComponents: .date)
                } footer: {
                    if dayTaken {
                        Text("그날은 이미 일기가 있어 옮기지 않았습니다.")
                    }
                }
                Section("목표") {
                    TextField("오늘의 목표", text: $entry.goal, axis: .vertical).lineLimit(1...4)
                }
                Section("실적") {
                    TextField("오늘 한 것", text: $entry.result, axis: .vertical).lineLimit(1...4)
                }
                Section("감사") {
                    TextField("오늘 감사한 것", text: $entry.gratitude, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle(DiaryCard.dayText(entry.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            // 날짜 피커는 시각까지 들고 오므로 자정으로 맞춘다 — 하루에 하나라는
            // 약속(`day` 비교)이 그래야 지켜진다. **이미 일기가 있는 날로는 못
            // 옮긴다** — 둘이 되면 현황판이 어느 쪽을 오늘로 보일지 정할 수 없다.
            .onChange(of: entry.day) { old, value in
                let start = Calendar.current.startOfDay(for: value)
                if start != value { entry.day = start; return }
                if reverting { reverting = false; return }
                let taken = !context.all(DiaryEntry.self,
                                         predicate: NSPredicate(format: "day == %@ AND SELF != %@",
                                                                start as NSDate, entry)).isEmpty
                dayTaken = taken
                if taken { reverting = true; entry.day = old }
            }
        }
    }
}
