import CoreData
import SwiftUI

/// **편집 권한 — 참가자마다 고칠 수 있는 구성원** (docs/09-family-sharing.md 4단계).
///
/// 엄마는 엄마·아들 것, 아들은 아들 것 — 관리자가 여기서 체크한다. 체크는
/// `Member.editorIDs` 에 적혀 가구와 함께 모든 기기에 퍼지고, 참가자 기기는
/// 제 ID 가 적힌 구성원만 고친다.
///
/// `CKShare` 권한도 여기서 맞춘다. 서버 권한이 보기 전용이면 앱이 열어 줘도
/// 저장이 튕기므로, 한 사람에게 체크가 하나라도 켜지면 변경 가능으로, 전부
/// 꺼지면 보기 전용으로 되쓴다. 두 군데를 오갈 필요가 없다.
struct EditGrantsView: View {
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @State private var sharing = FamilySharing.shared

    var body: some View {
        Form {
            if sharing.state.people.isEmpty {
                Section {
                    Text("아직 참가자가 없습니다. 초대를 받아들인 사람이 여기에 나타납니다.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                }
            }
            ForEach(sharing.state.people) { person in
                Section {
                    ForEach(members) { member in
                        Toggle(isOn: binding(person, member)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.member(member.colorIndex))
                                    .frame(width: 10, height: 10)
                                Text(member.name.isEmpty ? "이름 없음" : member.name)
                            }
                        }
                    }
                } header: {
                    Text(person.name)
                } footer: {
                    // ID 꼬리는 참가자 기기의 "내 참가자 ID" 와 견주는 용도다.
                    Text((person.accepted
                          ? (person.canWrite ? "변경 가능 · 체크한 구성원의 계좌·종목을 고칩니다. 체크를 끄기 전에 상대 기기의 동기화(더보기 → 동기화 → 마지막 내보내기: 성공)가 끝났는지 보세요 — 밀린 기록은 권한이 없어지면 못 올라옵니다."
                                             : "보기 전용 · 구성원을 체크하면 변경 가능으로 바뀝니다.")
                          : "아직 초대를 받아들이지 않았습니다.")
                         + " · ID \(FamilyShareSection.tail(person.id))")
                }
            }
            if let result = sharing.lastPermissionResult {
                Section {
                    Text(result)
                        .font(.system(size: 11.5))
                        .foregroundStyle(result.contains("못했") ? Color.loss : Color.muted)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("편집 권한")
        .navigationBarTitleDisplayMode(.inline)
        .task { sharing.refreshState() }
    }

    private func binding(_ person: SharePerson, _ member: Member) -> Binding<Bool> {
        Binding(
            get: { member.grants(person.id) },
            set: { on in
                member.setGrant(person.id, on)
                // 이 사람에게 켜진 체크가 하나라도 있으면 서버 권한도 변경 가능이어야 한다.
                let anyGrant = members.contains { $0.grants(person.id) }
                if anyGrant != person.canWrite {
                    sharing.setPermission(canWrite: anyGrant, for: person.id)
                }
            }
        )
    }
}
