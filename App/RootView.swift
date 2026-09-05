import Core
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var selection = RootView.initialTab
    @State private var route = AppRoute.shared

    @Query private var holdings: [Holding]
    @Query private var sessions: [ReviewSession]

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("현황판", systemImage: "chart.bar") }
                .tag(0)

            AssetsView()
                .tabItem { Label("자산", systemImage: "list.bullet") }
                .tag(1)

            PlanView()
                .tabItem { Label("계획", systemImage: "calendar") }
                .tag(2)

            ComingSoonView(title: "시뮬레이션", detail: "월 적립액 · 은퇴 나이 · 기대수익률 What-if")
                .tabItem { Label("시뮬레이션", systemImage: "slider.horizontal.3") }
                .tag(3)

            MoreView()
                .tabItem { Label("더보기", systemImage: "ellipsis") }
                .tag(4)
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

    /// CI 스크린샷이 화면마다 한 장씩 찍을 수 있도록 시작 탭을 실행 인자로 받는다.
    /// `xcrun simctl launch <udid> <bundle> -startTab assets`
    private static var initialTab: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startTab"),
              arguments.indices.contains(index + 1) else { return 0 }
        switch arguments[index + 1] {
        case "assets": return 1
        case "plan": return 2
        case "simulation": return 3
        case "more": return 4
        default: return 0
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("준비 중")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
