import Core
import CoreData
import SwiftUI

/// 직접 찍는 마일스톤.
///
/// 자동 판정(수익 > 적립금 · 자산 2배 · 목표 달성)이 담지 못하는 것들이 있다.
/// "첫째 대학 입학", "전세 만기", "차 교체". 금액이 아니라 **연도에 이름을 붙이는
/// 일**이라 사용자만 할 수 있다.
///
/// **로드맵에는 얹히지 않는다.** 로드맵의 뼈대는 여섯 칸으로 고정했고
/// (docs/08-feedback.md 5번), 마일스톤은 현황판의 `인생 이벤트` 줄과 순자산
/// 궤적의 세로 눈금으로 간다. 누구의 일인지도 고를 수 있다 (32번).
struct MilestoneListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEdit) private var canEdit
    @Fetched(sort: \UserMilestone.year) private var milestones: [UserMilestone]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @State private var editing: UserMilestone?
    /// 방금 만든 것의 id — 편집 시트의 `취소` 가 지운다 (104번).
    @State private var newIDs: Set<UUID> = []
    @State private var pendingDelete: IndexSet?

    var body: some View {
        List {
            if milestones.isEmpty {
                Section {
                    Text("자동으로 판정되는 마일스톤(자산 2배 · 수익 > 적립금 · 목표 달성)은 이미 로드맵에 있습니다.\n여기에는 앱이 알 수 없는 것을 적습니다 — 아이 대학 입학, 전세 만기 같은 것들.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            ForEach(milestones) { milestone in
                // 보기 전용이면 버튼으로 두지 않는다 — 눌러도 아무 일이 없는
                // 버튼은 잠긴 화면이 아니라 고장 난 화면으로 읽힌다.
                if canEdit {
                    Button { editing = milestone } label: { row(milestone) }
                } else {
                    row(milestone)
                }
            }
            .onDelete(perform: canEdit
                      ? { (offsets: IndexSet) in pendingDelete = offsets } : nil)
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
                if canEdit {
                    Button {
                        let milestone = UserMilestone(context: context, sortIndex: milestones.count)
                        newIDs.insert(milestone.id)
                        editing = milestone
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing, onDismiss: { newIDs.removeAll() }) {
            MilestoneEditView(milestone: $0, isNew: newIDs.contains($0.id))
        }
    }

    private func row(_ milestone: UserMilestone) -> some View {
        HStack {
            Text(verbatim: "\(milestone.year)")
                .font(.figure(14, weight: .semibold))
                .foregroundStyle(Color.dad)
                .frame(width: Font.scaledLength(52), alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(milestone.label.isEmpty ? "이름 없음" : milestone.label)
                        .font(.scaled(13))
                        .foregroundStyle(Color.ink)
                    // 누구의 일인가. 가족 전체면 배지를 달지 않는다 —
                    // 대부분이 가족 일이라 배지가 다 붙으면 소용없다.
                    if let member = owner(of: milestone) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.member(member.colorIndex))
                                .frame(width: 6, height: 6)
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .font(.scaled(10))
                                .foregroundStyle(Color.muted)
                        }
                    }
                }
                if !milestone.note.isEmpty {
                    Text(milestone.note)
                        .font(.scaled(10.5))
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func owner(of milestone: UserMilestone) -> Member? {
        guard let id = milestone.memberID else { return nil }
        return members.first { $0.id == id }
    }
}

struct MilestoneEditView: View {
    @ObservedObject var milestone: UserMilestone
    /// 방금 만든 것인가 — 취소하면 지운다 (104번).
    var isNew = false
    @State private var snapshot: EditSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    /// `Picker` 는 옵셔널 태그를 직접 못 다룬다. 바인딩으로 감싼다.
    private var memberSelection: Binding<UUID?> {
        Binding(get: { milestone.memberID }, set: { milestone.memberID = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (첫째 대학 입학 …)", text: $milestone.label)
                    Stepper(value: $milestone.year, in: currentYear...(currentYear + 60)) {
                        Text(verbatim: "\(milestone.year)년")
                    }
                } footer: {
                    // 예전 문구는 "로드맵에 얹힙니다" 였는데 **틀린 말이었다** —
                    // 5번에서 로드맵의 뼈대를 여섯으로 못 박으면서 마일스톤은
                    // 궤적의 눈금으로 옮겼다. 어디에 보이는지 정확히 적는다.
                    Text("현황판의 **인생 이벤트** 줄에 뜨고, 순자산 궤적의 세로 눈금으로도 표시됩니다. 그때의 예상 자산도 함께 보입니다.")
                }

                Section {
                    Picker("누구의 일", selection: memberSelection) {
                        Text("가족 전체").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .tag(UUID?.some(member.id))
                        }
                    }
                } footer: {
                    Text("사람을 고르면 그 사람의 궤적 화면에도 함께 뜨고, 현황판에서 **그 해의 나이**를 같이 보여줍니다. 전세 만기처럼 가족 전체의 일은 그대로 두세요.")
                }

                Section("메모") {
                    TextField("자세한 내용", text: $milestone.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if !isNew {
                    Section {
                        DeleteButton("\(milestone.label.isEmpty ? "이 마일스톤" : milestone.label) 을(를) 삭제할까요?",
                                     consequence: "되돌릴 수 없습니다.") {
                            context.delete(milestone)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("마일스톤")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if snapshot == nil { snapshot = EditSnapshot(of: milestone) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func cancel() {
        if isNew { context.delete(milestone) } else { snapshot?.restore(to: milestone) }
        dismiss()
    }
}
