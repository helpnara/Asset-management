import CloudKit
import CoreData
import SwiftUI

/// **가족 초대.** 여기서 만든 `CKShare` 한 장이 가구 전체를 따라다닌다
/// (docs/09-family-sharing.md 2b).
struct FamilyShareSection: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canManageHousehold) private var canManageHousehold

    @Fetched private var plans: [Plan]

    @State private var sharing = FamilySharing.shared
    /// **앱이 지금 무엇을 믿고 있나.** 화면에 그대로 내놓는다.
    @State private var state = ShareState()

    struct ShareState {
        var households = 0
        var hasLocalShare = false
        var isSaved = false
        var participants = 0

        /// 사람이 읽을 한 줄.
        var label: String {
            if households == 0 { return "아직 없음" }
            if !hasLocalShare { return "공유 안 함" }
            if !isSaved { return "만들다 만 상태" }
            return "공유 중 · 참가자 \(participants)명"
        }

        var isTrouble: Bool { households > 1 || (hasLocalShare && !isSaved) }
    }

    var body: some View {
        Section {
            if canManageHousehold {
                Button {
                    // **공유를 미리 만들지 않고, SwiftUI 시트에도 안 담는다.**
                    // 둘 다 기기에서 막혔다 — 앞은 "링크를 생성할 수 없습니다",
                    // 뒤는 빈 화면이었다 (FamilyShareSheet 참고).
                    FamilyShareSheet.present(titled: title)
                } label: {
                    HStack {
                        Text(state.isSaved ? "공유 관리" : "가족 초대")
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

            // **앱이 믿는 상태를 그대로 내놓는다.**
            //
            // "공유 관리를 눌렀는데 초대 화면이 뜬다" 로 한 바퀴를 썼다.
            // 실은 저장된 공유가 없어서 만들기 화면이 뜬 것이 맞았는데,
            // 앱이 그 사실을 아무 데도 안 보여 줘서 알 방법이 없었다.
            LabeledContent("상태") {
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state.isTrouble ? Color.loss
                                     : (state.isSaved ? Color.gain : Color.muted))
            }
            if state.households > 1 {
                Text("가구가 \(state.households)개입니다. 하나여야 합니다 — 공유가 엉뚱한 쪽에 붙을 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.loss)
            }

            // **왜 안 됐는지 그대로 내놓는다.** 시트의 알림은 "링크를 생성할
            // 수 없습니다" 까지만 말하고 CloudKit 오류 코드를 안 보여 준다.
            // 그 코드가 없어서 오늘 한 바퀴를 추측으로 버렸다. 길게 누르면
            // 복사된다.
            if let failure = sharing.lastFailure {
                VStack(alignment: .leading, spacing: 4) {
                    Text("공유가 안 된 이유")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.muted)
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.loss)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("가족")
        } footer: {
            Text(canManageHousehold
                 ? "초대하면 기록 전체가 상대 기기에도 보입니다. 기본은 **보기 전용**이고, 이 화면에서 사람마다 넓힐 수 있습니다."
                 : "관리자가 공유한 기록을 보고 있습니다.")
        }
        .task {
            state = readState()
        }
    }

    /// 상대가 초대 화면에서 볼 이름. 계획 제목이 곧 이 가족의 이름이다.
    private var title: String {
        plans.first?.title ?? "우리 가족"
    }

    /// **가구를 여기서 만들지 않는다.** 더보기를 열었다는 이유로 빈 가구가
    /// 생기면 안 된다. 만드는 것은 실제로 공유할 때다.
    /// **가구를 여기서 만들지 않는다.** 더보기를 열었다는 이유로 빈 가구가
    /// 생기면 안 된다. 만드는 것은 실제로 공유할 때다.
    private func readState() -> ShareState {
        var state = ShareState()
        state.households = Household.count(in: context)
        guard let household = context.all(
            Household.self,
            sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)]
        ).first else { return state }

        guard let share = sharing.existingShare(for: household) else { return state }
        state.hasLocalShare = true
        // **저장된 것만 "공유 중" 이다.** `url` 은 CloudKit 이 저장하면서
        // 붙여 주는 값이라, 만들다 만 것과 진짜를 가른다.
        state.isSaved = share.url != nil
        state.participants = share.participants.count
        return state
    }
}
