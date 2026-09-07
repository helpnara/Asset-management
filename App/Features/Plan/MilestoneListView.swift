import Core
import SwiftData
import SwiftUI

/// 직접 찍는 마일스톤.
///
/// 자동 판정(수익 > 적립금 · 자산 2배 · 목표 달성)이 담지 못하는 것들이 있다.
/// "첫째 대학 입학", "전세 만기", "차 교체". 금액이 아니라 **연도에 이름을 붙이는
/// 일**이라 사용자만 할 수 있다. 로드맵에 그대로 얹힌다.
struct MilestoneListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserMilestone.year) private var milestones: [UserMilestone]
    @State private var editing: UserMilestone?
    @State private var pendingDelete: IndexSet?

    var body: some View {
        List {
            if milestones.isEmpty {
                Section {
                    Text("자동으로 판정되는 마일스톤(자산 2배 · 수익 > 적립금 · 목표 달성)은 이미 로드맵에 있습니다.\n여기에는 앱이 알 수 없는 것을 적습니다 — 아이 대학 입학, 전세 만기 같은 것들.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            ForEach(milestones) { milestone in
                Button {
                    editing = milestone
                } label: {
                    HStack {
                        Text(verbatim: "\(milestone.year)")
                            .font(.figure(14, weight: .semibold))
                            .foregroundStyle(Color.dad)
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.label.isEmpty ? "이름 없음" : milestone.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.ink)
                            if !milestone.note.isEmpty {
                                Text(milestone.note)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.faint)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .onDelete { pendingDelete = $0 }
        }
        .confirmsDelete($pendingDelete, title: "이 마일스톤을 삭제할까요?",
                        message: "되돌릴 수 없습니다.") { offsets in
            for index in offsets where milestones.indices.contains(index) {
                context.delete(milestones[index])
            }
        }
        .navigationTitle("내 마일스톤")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let milestone = UserMilestone(sortIndex: milestones.count)
                    context.insert(milestone)
                    editing = milestone
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { MilestoneEditView(milestone: $0) }
    }
}

struct MilestoneEditView: View {
    @Bindable var milestone: UserMilestone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (첫째 대학 입학 …)", text: $milestone.label)
                    Stepper(value: $milestone.year, in: currentYear...(currentYear + 60)) {
                        Text(verbatim: "\(milestone.year)년")
                    }
                } footer: {
                    Text("현황판 로드맵에 이 연도로 얹힙니다. 그때의 예상 자산도 함께 보입니다.")
                }

                Section("메모") {
                    TextField("자세한 내용", text: $milestone.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("마일스톤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DeleteButton("\(milestone.title.isEmpty ? "이 마일스톤" : milestone.title) 을(를) 삭제할까요?",
                                 consequence: "되돌릴 수 없습니다.") {
                        context.delete(milestone)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
