import CoreData
import SwiftUI

/// **계획이 아직 없을 때 화면이 보여 주는 것** (167번).
///
/// 예전에는 계획이 없으면 그 자리에서 `Plan.current` 로 **바로 만들었다.**
/// 새 기기의 첫 실행은 iCloud 에서 계획이 내려오기 **전에** 이 자리를 지나므로,
/// 그 순간 빈 계획이 하나 생기고 뒤이어 진짜 계획이 내려와 **둘이 됐다** —
/// 아이패드가 9/11 에 그렇게 하나 만들었다. 셋 중 하나가 그것이다.
///
/// 이제는 **가져오기가 한 번 끝나고 도는 것이 없을 때**만 만든다. iCloud 가
/// 안 붙거나 오프라인이면 가져오기가 영영 안 끝나므로 **20초** 뒤에는 만든다 —
/// 첫 실행의 역할 판정(76번)과 같은 시한이다. iCloud 를 안 쓰는 모드(기기
/// 전용 · 체험)는 기다릴 것이 없으니 바로 만든다.
struct MissingPlanView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var monitor = CloudKitSyncMonitor.shared
    @State private var trial = TrialMode.shared
    @State private var waitExpired = false

    var body: some View {
        // 본문은 비워 두고 진행은 아래 띠가 보인다 (169번).
        Color.clear
        .reportsProgress("iCloud 에서 계획을 받아오는 중", when: !maySeed)
        .task {
            try? await Task.sleep(for: .seconds(20))
            waitExpired = true
        }
        .task(id: maySeed) {
            guard maySeed else { return }
            _ = Plan.current(in: context)
        }
    }

    /// 지금 만들어도 되나.
    private var maySeed: Bool {
        guard Persistence.mode == .cloudKit, !trial.isActive else { return true }
        if waitExpired { return true }
        return monitor.hasFinishedImport && monitor.importsInFlight == 0
    }
}
