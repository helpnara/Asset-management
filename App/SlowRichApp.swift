import CoreData
import SwiftUI
import UserNotifications

@main
struct SlowRichApp: App {
    private let container: NSPersistentContainer
    private let notifications: NotificationCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = AppLock.shared
    /// 체험 모드 (133번). 켜져 있으면 화면 전체가 체험 저장소를 본다.
    @State private var trial = TrialMode.shared

    /// 초대 링크를 받으려면 씬 델리게이트가 있어야 한다 (`ShareAcceptance.swift`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        // 동기화가 **실제로** 되는지 지켜본다. 저장소가 iCloud 모드로 열리고
        // 계정이 붙어 있어도 밀어 넣기는 전부 실패하고 있을 수 있다
        // (Production 스키마에 레코드 타입이 없을 때가 그렇다).
        MainActor.assumeIsolated { CloudKitSyncMonitor.shared.start() }
        // **저장을 켠다.** Core Data 는 스스로 저장하지 않는다 —
        // SwiftData 에서 갈아탈 때 조용히 사라진 것이다 (Autosave 참고).
        MainActor.assumeIsolated { Autosave.shared.start(container.viewContext) }
    }

    /// CI 스크린샷은 매 실행마다 환영 화면에 막히면 안 되므로 실행 인자로 건너뛴다.
    private var needsOnboarding: Bool {
        !onboardingCompleted && !ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    // 체험을 켜고 끌 때 화면을 통째로 새로 만든다 — `@FetchRequest`
                    // 가 컨텍스트를 바꿔 물게 하는 가장 확실한 길이다.
                    .id(trial.isActive)
                    .fullScreenCover(isPresented: .constant(needsOnboarding)) {
                        WelcomeView(onFinish: { onboardingCompleted = true },
                                    onTrial: {
                                        trial.begin()
                                        onboardingCompleted = true
                                    })
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
            // **`.background` 에서만 잠근다.** `.inactive` 는 앱 전환기·제어 센터뿐
            // 아니라 **Face ID 창이 뜰 때도** 온다. 거기서 잠그면 인증하려는 순간
            // 스스로 판을 엎고, 시스템이 그 평가를 취소한다 — 실제로
            // "인증이 취소되었습니다" 가 반복해서 났다 (docs/08-feedback.md 4번).
            if phase == .background { lock.lock() }
            // **내려가기 전에 쓴다.** `.inactive` 부터 잡는다 — 앱 전환기에
            // 올라간 순간 사용자가 쓸어 올려 끝낼 수 있고, 그때는 `.background`
            // 가 안 올 수도 있다. 모아 둔 것이 없으면 아무 일도 안 한다.
            if phase != .active { Autosave.shared.flush() }
        }
        // SwiftData 의 `.modelContainer(_:)` 자리. Core Data 는 컨텍스트를
        // 환경으로 내리고, `@Fetched` 가 그것을 읽는다.
        .environment(\.managedObjectContext, (trial.container ?? container).viewContext)
    }
}
