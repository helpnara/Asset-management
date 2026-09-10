import Core
import CoreData
import SwiftUI

struct RootView: View {
    @State private var route = AppRoute.shared
    @State private var sharing = FamilySharing.shared
    @State private var monitor = CloudKitSyncMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    /// 역할 확인을 이만큼은 기다린다. 그 뒤에는 아는 대로 연다 — 오프라인
    /// 첫 실행에서 영영 잠긴 채 서 있으면 안 된다 (76번).
    @State private var roleWaitExpired = false


    @Fetched private var holdings: [Holding]
    @Fetched private var sessions: [ReviewSession]
    @Fetched(sort: \TodoItem.sortIndex) private var todos: [TodoItem]
    @Fetched private var accounts: [Account]
    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var diary: [DiaryEntry]

    /// **역할은 `CKShare` 가 정한다** (docs/09-family-sharing.md 4단계). 초대를
    /// 받아들인 기기는 참가자 권한대로, 나머지는 소유자다. 실행 인자는 CI 가
    /// 보기 전용 화면을 찍을 때만 쓴다 — 기기에서 역할을 흉내 내는 토글은
    /// 실제 공유가 확인된 뒤 지웠다 (2026-09-10).
    private var role: FamilyRole {
        if let preview = RolePreview.launchArgument { return preview }
        // **아직 모르는 동안은 잠근다** (76번). 이 기기가 한 번도 역할을 판정한
        // 적이 없고 가져오기도 안 끝났으면, 참가자 폰의 첫 실행일 수 있다 —
        // 그때 소유자로 열어 두면 남의 것을 고치다 나중에 잠긴다.
        if isRolePending { return .viewer }
        if sharing.state.isParticipant { return sharing.state.role }
        return .owner
    }

    /// 첫 실행에서 역할 판정이 끝나기를 기다리는 중인가. iCloud 모드에서만,
    /// 기억한 역할이 없을 때만, 그리고 20초까지만.
    private var isRolePending: Bool {
        guard Persistence.mode == .cloudKit, !roleWaitExpired,
              UserDefaults.standard.string(forKey: FamilySharing.roleKey) == nil else { return false }
        return !sharing.state.isResolved || !monitor.hasFinishedImport
    }

    /// 참가자였는데 공유가 사라졌다 — 가져오기가 끝난 뒤에도 그렇다면 진짜다 (79번).
    private var isShareLost: Bool {
        sharing.state.shareLost && monitor.hasFinishedImport
    }

    var body: some View {
        tabs
            .familyRole(role, participantID: sharing.state.participantID)
            .safeAreaInset(edge: .top, spacing: 0) { notices }
            // 역할은 앱이 뜰 때와 앞으로 돌아올 때 다시 읽는다. 관리자가 권한을
            // 넓혀 주면 참가자 쪽은 다음에 앞으로 왔을 때 편집이 열린다.
            .task { sharing.refreshState() }
            .task {
                try? await Task.sleep(for: .seconds(20))
                roleWaitExpired = true
            }
            // 가져오기가 끝나면 한 번 더 읽는다 — 첫 실행의 참가자 폰은 이때
            // 비로소 공유가 손에 들어온다 (76번).
            .onChange(of: monitor.hasFinishedImport) { _, finished in
                if finished { sharing.refreshState() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    sharing.refreshState()
                    let written = DiaryNotifications.todayWritten(diary)
                    Task { await DiaryNotifications.refresh(todayWritten: written) }
                }
            }
    }

    /// 화면 위의 한 줄 알림. 없으면 자리도 없다.
    @ViewBuilder
    private var notices: some View {
        if isRolePending {
            noticeBar(icon: "icloud", text: "iCloud 에서 역할을 확인하는 중 — 잠시 뒤 편집이 열립니다",
                      spinning: true)
        } else if isShareLost {
            noticeBar(icon: "person.2.slash",
                      text: "가족 공유가 끊긴 것 같습니다 · 더보기 → 가족에서 확인하세요",
                      spinning: false)
        }
    }

    private func noticeBar(icon: String, text: String, spinning: Bool) -> some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.alertSoft)
    }

    private var tabs: some View {
        TabView(selection: $route.selectedTab) {
            DashboardView()
                .tabItem { Label("현황판", systemImage: "chart.bar") }
                .tag(Tab.dashboard)

            AssetsView()
                .tabItem { Label("자산", systemImage: "list.bullet") }
                .tag(Tab.assets)

            PlanView()
                .tabItem { Label("계획", systemImage: "calendar") }
                .tag(Tab.plan)

            SimulationView()
                .tabItem { Label("시뮬레이션", systemImage: "slider.horizontal.3") }
                .tag(Tab.simulation)

            MoreView()
                .tabItem { Label("더보기", systemImage: "ellipsis") }
                .tag(Tab.more)
        }
        .tint(Color.ink)
        // 숫자 키패드에는 return 키가 없다. `완료` 버튼(MoneyField)에 더해
        // **쓸어내려도 닫히게** 한다. 이 값은 환경으로 내려가므로 여기 한 번이면
        // 아래의 모든 Form·List·ScrollView 에 걸린다 (docs/08-feedback.md 2번).
        .scrollDismissesKeyboard(.interactively)
        // **탭 화면의 바탕은 하나다** (docs/08-feedback.md 35번).
        // 목록 화면들이 이미 시스템 목록 바탕을 쓰고 있으므로 거기에 맞춘다.
        .background(Color.ground)
        .task {
            // 시간대 변경·기기 이전에 대비해 앱이 뜰 때마다 다시 등록한다.
            let input = ReviewScheduling.Input(holdings: holdings, sessions: sessions)
            await ReviewScheduling.refresh(input)

            // 기한 알림은 주간 점검과 따로 건다. 시간대 변경·기기 이전에 대비해
            // 여기서도 통째로 다시 건다.
            let todoInput = TodoNotifications.Input(items: todos, accounts: accounts)
            await TodoNotifications.refresh(todoInput)

            // 일기 알림도 같은 이유로 여기서 다시 건다. "오늘 이미 적었나" 가
            // 트리거 모양을 정하므로 앞으로 올 때마다도 본다.
            await DiaryNotifications.refresh(todayWritten: DiaryNotifications.todayWritten(diary))
        }
        .fullScreenCover(isPresented: Binding(
            // 알림을 눌러 들어오는 길도 막는다 — 보기 전용이면 적을 화면이 없다.
            get: { route.showReview && role.canEdit },
            set: { route.showReview = $0 }
        )) {
            WeeklyReviewView()
        }
        .alert("이번 주 기록 완료",
               isPresented: Binding(
                   get: { route.totalOnlyMessage != nil },
                   set: { if !$0 { route.totalOnlyMessage = nil } }
               ),
               presenting: route.totalOnlyMessage) { _ in
            Button("확인", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// 탭 번호를 여기저기 리터럴로 적으면 하나 끼워 넣을 때 조용히 어긋난다.
    enum Tab {
        static let dashboard = 0
        static let assets = 1
        static let plan = 2
        static let simulation = 3
        static let more = 4
    }

    /// CI 스크린샷이 화면마다 한 장씩 찍을 수 있도록 시작 탭을 실행 인자로 받는다.
    /// `xcrun simctl launch <udid> <bundle> -startTab assets`
    static var initialTab: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startTab"),
              arguments.indices.contains(index + 1) else { return Tab.dashboard }
        switch arguments[index + 1] {
        case "assets": return Tab.assets
        case "plan": return Tab.plan
        case "simulation": return Tab.simulation
        case "more": return Tab.more
        default: return Tab.dashboard
        }
    }
}
