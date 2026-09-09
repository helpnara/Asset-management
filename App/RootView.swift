import Core
import CoreData
import SwiftUI

struct RootView: View {
    @State private var route = AppRoute.shared
    @State private var sharing = FamilySharing.shared
    @Environment(\.scenePhase) private var scenePhase

    /// 지금 어느 역할로 보고 있나 (docs/09-family-sharing.md 4단계).
    /// 공유가 붙기 전까지는 더보기의 토글이 이 값을 바꾼다.
    @AppStorage(RolePreview.key) private var previewedRole = FamilyRole.owner.rawValue

    @Fetched private var holdings: [Holding]
    @Fetched private var sessions: [ReviewSession]
    @Fetched(sort: \TodoItem.sortIndex) private var todos: [TodoItem]
    @Fetched private var accounts: [Account]

    /// **진짜 역할이 먼저다.** 초대를 받아들인 기기는 `CKShare` 가 정한 역할로
    /// 보고, 미리보기 토글은 무시한다 — 참가자가 토글로 관리자 화면을 열면
    /// 눌러도 서버가 거부하는 버튼이 널린 화면이 된다.
    /// 소유자 기기에서는 전처럼 실행 인자 → 미리보기 순이다.
    private var role: FamilyRole {
        if sharing.state.isParticipant { return sharing.state.role }
        return RolePreview.launchArgument ?? FamilyRole(rawValue: previewedRole) ?? .owner
    }

    var body: some View {
        VStack(spacing: 0) {
            // **미리보기 중이라는 것을 늘 보이게 둔다.** 이 띠가 없으면 왜
            // 버튼이 안 눌리는지 몰라 고장으로 읽는다. 진짜 참가자에게는
            // 안 띄운다 — 그 사람에게는 이것이 미리보기가 아니라 제 화면이다.
            if role != .owner && !sharing.state.isParticipant {
                RolePreviewBanner(role: role) { previewedRole = FamilyRole.owner.rawValue }
            }
            tabs
        }
        .familyRole(role)
        // 역할은 앱이 뜰 때와 앞으로 돌아올 때 다시 읽는다. 관리자가 권한을
        // 넓혀 주면 참가자 쪽은 다음에 앞으로 왔을 때 편집이 열린다.
        .task { sharing.refreshState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sharing.refreshState() }
        }
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
