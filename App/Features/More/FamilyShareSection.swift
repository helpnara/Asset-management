import SwiftUI

/// **가족 초대.** 여기서 만든 `CKShare` 한 장이 가구 전체를 따라다닌다
/// (docs/09-family-sharing.md 2b).
struct FamilyShareSection: View {
    @Environment(\.canManageHousehold) private var canManageHousehold

    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Environment(\.self) private var environment

    @State private var sharing = FamilySharing.shared
    @State private var monitor = CloudKitSyncMonitor.shared
    @State private var isConfirmingMove = false
    @State private var isConfirmingForget = false
    /// 이력에 남을 이름 (74번). 이 기기에만 저장된다.
    @AppStorage(ActorName.key) private var actorName = ""

    var body: some View {
        familySection
        // **만일에 대비** (78번). 관리자 폰을 잃어버리면 어떻게 되나 — 물어보기
        // 전에 적어 둔다. 공유 소유권은 옮길 수 없다는 것이 핵심이다.
        if canManageHousehold && !sharing.state.isParticipant && sharing.state.isSaved {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    contingencyLine("폰을 잃어버리면", "기록은 관리자의 Apple 계정 iCloud 에 있습니다. 새 폰에 같은 계정으로 로그인해 앱을 설치하면 기록과 가족 공유가 그대로 돌아옵니다.")
                    contingencyLine("Apple 계정을 못 쓰게 되면", "공유도 함께 사라집니다. 전체 백업 파일로 되돌리고 가족을 다시 초대합니다 — 백업은 달에 한 번 받아 두세요.")
                    contingencyLine("관리자를 바꾸려면", "공유 소유권은 옮길 수 없습니다. 새 관리자 폰에서 백업을 되돌리고 새로 초대합니다. 옛 관리자는 공유를 중단합니다.")
                }
            } header: {
                Text("만일에 대비")
            }
        }
    }

    private func contingencyLine(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(Color.muted)
                .lineSpacing(2)
        }
    }

    private var familySection: some View {
        Section {
            // 초대를 받아들인 기기는 참가자다 — 역할 미리보기가 뭐라고 하든.
            // 참가자 쪽에서 "가족 초대" 를 내놓으면 공유가 둘이 된다.
            if canManageHousehold && !sharing.didAcceptInvitation && !sharing.state.isParticipant {
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
                LabeledContent("가족 공유", value: sharing.state.isParticipant
                               ? "참가 중 · \(sharing.state.role.label)" : "참가 중")

                // **권한이 왜 안 열리는지 그 자리에서 판별한다.** 관리자가 체크했는데
                // 참가자 화면이 안 열리면 셋 중 하나다 — 구성원 칸이 아직 안
                // 내려왔거나(동기화·스키마), 참가자 ID 가 다르거나, 서버 권한이
                // 보기 전용이거나. ID 꼬리와 받은 구성원을 적어 두면 어느 쪽인지
                // 두 화면을 견줘 알 수 있다.
                if sharing.state.isParticipant {
                    let granted = members.filter { environment.mayEdit($0) }.map(\.name)
                    LabeledContent("받은 구성원", value: granted.isEmpty ? "없음" : granted.joined(separator: ", "))
                    // 이름을 앞에, ID 꼬리는 그 뒤에 작게 (77번). 꼬리는 관리자
                    // 화면의 편집 권한과 견주는 용도로만 남긴다.
                    LabeledContent("나") {
                        HStack(spacing: 6) {
                            Text(ActorName.current)
                                .font(.system(size: 13, weight: .medium))
                            Text(Self.tail(sharing.state.participantID))
                                .font(.figure(11))
                                .foregroundStyle(Color.faint)
                        }
                    }
                    if sharing.state.strays > 0 {
                        Text("개인 저장소에 남은 가족 기록이 \(sharing.state.strays)건 있습니다. 이 기록은 상대 기기에 안 갑니다 — 지우고 다시 만드세요 (빌드 58 부터는 새 기록이 공유 저장소로 갑니다).")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.loss)
                    }
                }
            }

            // 참가자마다 고칠 수 있는 구성원을 정하는 곳. 수락한 참가자가 있어야
            // 재료가 있다 — 그 전에는 "참가자 없음" 으로 보인다.
            if canManageHousehold && !sharing.state.isParticipant && sharing.state.isSaved {
                NavigationLink(value: MoreView.Destination.editGrants) {
                    HStack {
                        Text("편집 권한")
                        Spacer()
                        Text(sharing.state.people.isEmpty ? "참가자 없음" : "참가자 \(sharing.state.people.count)명")
                            .foregroundStyle(Color.muted)
                    }
                }
            }

            // **이력에 남을 이름** (74번). `ChangeLog.actor` 가 이 값을 받는다.
            // 기기 이름은 iOS 16 부터 "iPhone" 이라 쓸모가 없었다.
            HStack {
                Text("이력에 남을 이름")
                Spacer(minLength: 12)
                TextField(ActorName.current, text: $actorName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }

            // **공유가 끊겼다** (79번). 참가자로 기억하는데 공유 저장소에
            // `CKShare` 가 없고, 가져오기도 끝났다. 관리자가 뺀 것이다.
            if sharing.state.shareLost && monitor.hasFinishedImport {
                VStack(alignment: .leading, spacing: 6) {
                    Text("가족 공유가 끊긴 것 같습니다")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.loss)
                    Text("관리자가 이 기기를 참가자에서 빼거나 공유를 중단하면 이렇게 됩니다. 다시 함께 쓰려면 관리자에게 초대 링크를 새로 받으세요. 이 기기에서 혼자 새로 시작하려면 아래를 누르세요 — 관리자의 기록은 그대로입니다.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.muted)
                    Button("참가자 상태 지우고 새로 시작") { isConfirmingForget = true }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.loss)
                        .confirmationDialog("참가자 상태를 지울까요?", isPresented: $isConfirmingForget,
                                            titleVisibility: .visible) {
                            Button("지우기", role: .destructive) { sharing.forgetParticipation() }
                            Button("취소", role: .cancel) {}
                        } message: {
                            Text("이 기기는 관리자 없이 제 기록을 새로 시작합니다. 관리자에게 다시 초대받으면 그때 다시 참가자가 됩니다.")
                        }
                }
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
                Text("가구가 \(sharing.state.households)개입니다. 하나여야 합니다 — 공유가 엉뚱한 쪽에 붙을 수 있습니다."
                     + (sharing.state.pruneBlockers.map { " 못 치우는 이유: \($0)" } ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.loss)
                    .textSelection(.enabled)
            }
            if sharing.state.orphans > 0 {
                Text("공유에 안 실린 기록이 \(sharing.state.orphans)건 있습니다. 이 기록은 상대 기기에 안 보입니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.loss)
                if canManageHousehold && !sharing.state.isParticipant {
                    Button {
                        isConfirmingMove = true
                    } label: {
                        Text("기록 \(sharing.state.orphans)건을 공유로 옮기기")
                    }
                    .confirmationDialog("먼저 백업을 받으셨나요?", isPresented: $isConfirmingMove,
                                        titleVisibility: .visible) {
                        Button("백업 받았음 — 옮기기") { sharing.moveUnsharedIntoShare() }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("더보기 → 내보내기 → 전체 백업을 먼저 받으세요. 옮기기는 개인 저장소에서 지우고 공유 저장소에 새로 만드는 두 단계라, 실패하면 다른 기기의 기록이 잠시 사라질 수 있습니다. 한 기기에서만 누르세요.")
                    }
                }
            }
            if let adoption = sharing.lastAdoption {
                Text(adoption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
                    .textSelection(.enabled)
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
                 ? "초대하면 기록 전체가 상대 기기에도 보입니다. 기본은 **보기 전용**이고, [편집 권한]에서 참가자마다 고칠 수 있는 구성원을 정합니다."
                 : "관리자가 공유한 기록을 보고 있습니다. 관리자가 편집 권한을 주면 그 구성원의 계좌·종목을 고칠 수 있습니다.")
        }
        .task {
            // **메인에서 읽지 않는다.** 공유 조회는 Core Data 의 같은 실행기를
            // 쓰는데, 그것이 메인을 붙잡으면 워치독이 앱을 죽인다.
            sharing.refreshState()
        }
    }

    /// ID 는 길다 — 견주는 데는 꼬리 여섯 자면 된다.
    static func tail(_ id: String?) -> String { ActorName.idTail(id) }

    /// 상대가 초대 화면에서 볼 이름. 계획 제목이 곧 이 가족의 이름이다.
    private var title: String {
        plans.first?.title ?? "우리 가족"
    }

}
