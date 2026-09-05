import SwiftData
import SwiftUI
import UserNotifications

@main
struct SlowRichApp: App {
    private let container: ModelContainer
    private let notifications: NotificationCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = AppLock.shared

    /// 첫 실행에만 환영 화면을 띄운다. RootView 가 아니라 여기에 두는 이유는
    /// RootView 가 이미 주간 점검용 `fullScreenCover` 를 쓰고 있어서,
    /// 같은 뷰에 둘을 겹치면 서로를 막기 때문이다.
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    init() {
        let container = Persistence.shared.container
        self.container = container
        self.notifications = NotificationCoordinator(container: container)

        UNUserNotificationCenter.current().delegate = notifications
        ReviewNotifications.registerCategories()
    }

    /// CI 스크린샷은 매 실행마다 환영 화면에 막히면 안 되므로 실행 인자로 건너뛴다.
    private var needsOnboarding: Bool {
        !onboardingCompleted && !ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .fullScreenCover(isPresented: .constant(needsOnboarding)) {
                        WelcomeView { onboardingCompleted = true }
                    }

                // 잠금은 화면 위를 통째로 덮는다. 아래를 흐리게만 두면
                // 앱 전환기 미리보기에 금액이 그대로 남는다.
                if !lock.isUnlocked {
                    LockedOverlay()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: lock.isUnlocked)
        }
        .onChange(of: scenePhase) { _, phase in
            // 백그라운드로 갈 때 잠근다. 홈 화면으로 나갔다 돌아오면 다시 묻는다.
            if phase != .active { lock.lock() }
        }
        .modelContainer(container)
    }
}
