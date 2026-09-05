import SwiftData
import SwiftUI

@main
struct SlowRichApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
    }
}
