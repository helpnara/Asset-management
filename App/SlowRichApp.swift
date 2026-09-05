import SwiftData
import SwiftUI
import UserNotifications

@main
struct SlowRichApp: App {
    private let container: ModelContainer
    private let notifications: NotificationCoordinator

    init() {
        let container = Persistence.container
        self.container = container
        self.notifications = NotificationCoordinator(container: container)

        UNUserNotificationCenter.current().delegate = notifications
        ReviewNotifications.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
