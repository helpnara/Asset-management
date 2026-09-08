import CloudKit
import UIKit

/// **초대 링크를 받는 자리** (docs/09-family-sharing.md 2b).
///
/// SwiftUI 의 `App` 은 이 콜백을 안 준다. 링크로 열렸을 때 iOS 가 부르는 것은
/// **씬 델리게이트**의 `userDidAcceptCloudKitShareWith` 라, 앱 델리게이트를
/// 붙여 씬 델리게이트 클래스를 지정해야 한다. SwiftUI 는 그 위에서 그대로
/// `WindowGroup` 을 띄운다 — 애플이 문서화한 방식이다.
///
/// 두 길이 있다:
///  · 앱이 떠 있을 때 링크를 누름 → `windowScene(_:userDidAcceptCloudKitShareWith:)`
///  · 앱이 꺼진 채로 링크를 누름 → `scene(_:willConnectTo:options:)` 의
///    `cloudKitShareMetadata`
/// 둘 다 받아야 한다. 하나만 받으면 "어떨 땐 되고 어떨 땐 안 되는" 앱이 된다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil,
                                                 sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// 앱이 꺼진 채로 링크를 눌렀을 때.
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        MainActor.assumeIsolated { FamilySharing.shared.accept(metadata) }
    }

    /// 앱이 떠 있을 때 링크를 눌렀을 때.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        MainActor.assumeIsolated { FamilySharing.shared.accept(cloudKitShareMetadata) }
    }
}
