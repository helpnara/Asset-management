import SwiftUI

/// **"아직 없는 것" 과 "아직 안 온 것" 을 가른다** (docs/08-feedback.md 53번).
///
/// 아내분 폰에서 초대를 받아들인 직후 1~2분 동안 현황판이 "아직 등록된 자산이
/// 없습니다" 였다. 틀린 말이다 — 있는데 아직 안 온 것이다. 빈 화면에 "구성원을
/// 추가하세요" 까지 붙어 있으면 참가자는 무언가를 잘못했다고 읽는다.
///
/// 언제 "받아오는 중" 으로 보나. iCloud 모드이고 자료가 비어 있는데,
/// · 가져오기가 지금 돌고 있거나
/// · 이번 실행에서 가져오기가 아직 한 번도 안 끝났거나
/// · 참가자다 (참가자의 자료는 전부 관리자에게서 온다)
/// 셋 중 하나면 그렇다. 가져오기가 끝났는데도 비어 있으면 진짜 빈 것이다.
struct SyncLoadingHint: View {
    @State private var monitor = CloudKitSyncMonitor.shared
    @State private var sharing = FamilySharing.shared

    /// 빈 상태 화면 대신 이것을 보여야 하나.
    @MainActor
    static var shouldShow: Bool {
        guard Persistence.mode == .cloudKit else { return false }
        let monitor = CloudKitSyncMonitor.shared
        return monitor.importsInFlight > 0
            || !monitor.hasFinishedImport
            || FamilySharing.shared.state.isParticipant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(sharing.state.isParticipant
                     ? "관리자가 공유한 기록을 받아오는 중"
                     : "iCloud 에서 기록을 받아오는 중")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            Text(sharing.state.isParticipant
                 ? "처음에는 1~2분 걸릴 수 있습니다. 화면이 그대로면 앱을 껐다 켜 보세요."
                 : "다른 기기에서 적은 기록이 있으면 곧 나타납니다. 처음 쓰는 기기라면 잠시 뒤 시작 화면이 뜹니다.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}
