import CloudKit
import CoreData
import SwiftUI

/// **가족 초대.** 여기서 만든 `CKShare` 한 장이 가구 전체를 따라다닌다
/// (docs/09-family-sharing.md 2b).
struct FamilyShareSection: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canManageHousehold) private var canManageHousehold

    @Fetched private var plans: [Plan]

    @State private var invite: FamilyInvite?
    @State private var failure: String?
    @State private var working = false
    /// 이미 공유가 있는지. 화면이 뜰 때 한 번 본다.
    @State private var alreadyShared = false

    var body: some View {
        Section {
            if canManageHousehold {
                Button {
                    start()
                } label: {
                    HStack {
                        Text(alreadyShared ? "공유 관리" : "가족 초대")
                        Spacer()
                        if working {
                            ProgressView()
                        } else {
                            Image(systemName: "person.2")
                                .foregroundStyle(Color.muted)
                        }
                    }
                }
                .disabled(working)
            } else {
                // 참가자에게는 초대 버튼을 안 내놓는다. `CKShare` 는 소유자만
                // 참가자를 더할 수 있어서, 눌러도 안 되는 버튼이 된다.
                LabeledContent("가족 공유", value: "참가 중")
            }

            if let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.loss)
                    .textSelection(.enabled)
            }
        } header: {
            Text("가족")
        } footer: {
            Text(canManageHousehold
                 ? "초대하면 기록 전체가 상대 기기에도 보입니다. 기본은 **보기 전용**이고, 이 화면에서 사람마다 넓힐 수 있습니다."
                 : "관리자가 공유한 기록을 보고 있습니다.")
        }
        .sheet(item: $invite) { invite in
            CloudSharingSheet(invite: invite, title: title)
                .ignoresSafeArea()
        }
        .task {
            // **가구를 여기서 만들지 않는다.** 저장할 때 `Household.attachNew`
            // 가 만든다. 여기서는 이미 있는 것만 본다 — 더보기를 열었다는
            // 이유로 빈 가구가 생기면 안 된다.
            guard let household = context.all(Household.self).first else { return }
            alreadyShared = FamilySharing.existingShare(for: household) != nil
        }
    }

    /// 상대가 초대 화면에서 볼 이름. 계획 제목이 곧 이 가족의 이름이다.
    private var title: String {
        plans.first?.title ?? "우리 가족"
    }

    private func start() {
        working = true
        failure = nil
        // 가구가 아직 없으면 여기서 만든다 — 공유하려면 뿌리가 있어야 한다.
        let household = Household.current(in: context)
        FamilySharing.share(household, titled: title) { result in
            working = false
            switch result {
            case .success(let made):
                invite = made
                alreadyShared = true
            case .failure(let error):
                failure = (error as NSError).localizedDescription
            }
        }
    }
}
