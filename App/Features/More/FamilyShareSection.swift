import CloudKit
import CoreData
import SwiftUI

/// **가족 초대.** 여기서 만든 `CKShare` 한 장이 가구 전체를 따라다닌다
/// (docs/09-family-sharing.md 2b).
struct FamilyShareSection: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canManageHousehold) private var canManageHousehold

    @Fetched private var plans: [Plan]

    @State private var presenting = false
    /// 이미 만들어 둔 공유. 없으면 `nil` 이고, 그때는 시트가 만든다.
    @State private var existing: FamilyInvite?

    var body: some View {
        Section {
            if canManageHousehold {
                Button {
                    // **공유를 미리 만들지 않는다.** 시트가 만들게 두는 것이
                    // 애플이 문서화한 길이고, 미리 만들어 넘겼다가 "링크를
                    // 생성할 수 없습니다" 로 막혔다 (FamilySharing 참고).
                    existing = currentInvite()
                    presenting = true
                } label: {
                    HStack {
                        Text(existing == nil ? "가족 초대" : "공유 관리")
                        Spacer()
                        Image(systemName: "person.2")
                            .foregroundStyle(Color.muted)
                    }
                }
            } else {
                // 참가자에게는 초대 버튼을 안 내놓는다. `CKShare` 는 소유자만
                // 참가자를 더할 수 있어서, 눌러도 안 되는 버튼이 된다.
                LabeledContent("가족 공유", value: "참가 중")
            }
        } header: {
            Text("가족")
        } footer: {
            Text(canManageHousehold
                 ? "초대하면 기록 전체가 상대 기기에도 보입니다. 기본은 **보기 전용**이고, 이 화면에서 사람마다 넓힐 수 있습니다."
                 : "관리자가 공유한 기록을 보고 있습니다.")
        }
        .sheet(isPresented: $presenting) {
            CloudSharingSheet(existing: existing, title: title)
                .ignoresSafeArea()
        }
        .task {
            existing = currentInvite()
        }
    }

    /// 상대가 초대 화면에서 볼 이름. 계획 제목이 곧 이 가족의 이름이다.
    private var title: String {
        plans.first?.title ?? "우리 가족"
    }

    /// **가구를 여기서 만들지 않는다.** 더보기를 열었다는 이유로 빈 가구가
    /// 생기면 안 된다. 만드는 것은 실제로 공유할 때다.
    private func currentInvite() -> FamilyInvite? {
        guard let household = context.all(Household.self).first,
              let share = FamilySharing.shared.existingShare(for: household) else { return nil }
        return FamilyInvite(share: share,
                            container: CKContainer(identifier: Persistence.cloudKitContainerID))
    }
}
