import Core
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var route = AppRoute.shared

    @Query private var holdings: [Holding]
    @Query private var sessions: [ReviewSession]

    var body: some View {
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
        .task {
            // 시간대 변경·기기 이전에 대비해 앱이 뜰 때마다 다시 등록한다.
            let input = ReviewScheduling.Input(holdings: holdings, sessions: sessions)
            await ReviewScheduling.refresh(input)
        }
        .fullScreenCover(isPresented: $route.showReview) {
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
