import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("현황판", systemImage: "chart.bar") }

            AssetsView()
                .tabItem { Label("자산", systemImage: "list.bullet") }

            ComingSoonView(title: "계획", detail: "적립 계획 · 연금 · 목돈 이벤트 · 마일스톤")
                .tabItem { Label("계획", systemImage: "calendar") }

            ComingSoonView(title: "시뮬레이션", detail: "월 적립액 · 은퇴 나이 · 기대수익률 What-if")
                .tabItem { Label("시뮬레이션", systemImage: "slider.horizontal.3") }

            ComingSoonView(title: "더보기", detail: "운용 원칙 · 유의사항 · 1페이지 내보내기 · 설정")
                .tabItem { Label("더보기", systemImage: "ellipsis") }
        }
        .tint(Color.ink)
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
