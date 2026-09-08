import SwiftUI

/// **가족 초대.** 여기서 만든 `CKShare` 한 장이 가구 전체를 따라다닌다
/// (docs/09-family-sharing.md 2b).
struct FamilyShareSection: View {
    @Environment(\.canManageHousehold) private var canManageHousehold

    @Fetched private var plans: [Plan]

    @State private var sharing = FamilySharing.shared

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
                        Text(sharing.state.isSaved ? "공유 관리" : "가족 초대")
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
                Text(sharing.state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(sharing.state.isTrouble ? Color.loss
                                     : (sharing.state.isSaved ? Color.gain : Color.muted))
            }
            if sharing.state.households > 1 {
                Text("가구가 \(sharing.state.households)개입니다. 하나여야 합니다 — 공유가 엉뚱한 쪽에 붙을 수 있습니다.")
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
            // **메인에서 읽지 않는다.** 공유 조회는 Core Data 의 같은 실행기를
            // 쓰는데, 그것이 메인을 붙잡으면 워치독이 앱을 죽인다.
            sharing.refreshState()
        }
    }

    /// 상대가 초대 화면에서 볼 이름. 계획 제목이 곧 이 가족의 이름이다.
    private var title: String {
        plans.first?.title ?? "우리 가족"
    }

}
