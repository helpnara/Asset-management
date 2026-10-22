import UIKit

/// **아이패드 사이드바를 보이고 숨긴다 — 탭 화면을 다시 만들지 않고** (206번).
///
/// 예전에는 가로(사이드바) · 세로(탭)를 `if` 로 갈라 `TabView` 를 두 벌 두었다. SwiftUI 에게 두 갈래는
/// 서로 다른 화면이라 **돌리는 순간 탭 안의 화면이 통째로 새로 만들어졌다** — 종목 편집 같은 시트가 닫히고,
/// 안쪽으로 들어간 화면이 첫 화면으로 돌아갔다(10-23 사용자 확인). 점검 창(199번 C4) · 궤적 크게 보기(204번)는
/// 탭 바깥으로 빼서 피했지만, 시트 19개 · 안쪽 화면 28곳을 다 뺄 수는 없다.
///
/// 그래서 아이패드(iOS 18 이상)는 **늘 `.sidebarAdaptable` 한 벌**로 두고, 가로 · 세로에 따라 사이드바만
/// 이 문으로 열고 닫는다. SwiftUI 에는 이 스타일의 사이드바를 여닫는 손잡이가 없어 속의 `UITabBarController`
/// 를 찾아 `sidebar.isHidden` 을 바꾼다. 못 찾으면 아무 일도 안 한다 — 사이드바 모양이 덜 맞을 뿐 화면은 산다.
@MainActor
enum TabSidebar {
    static func setVisible(_ visible: Bool) {
        guard #available(iOS 18.0, *) else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                guard let tabs = tabBarController(in: window.rootViewController) else { continue }
                if tabs.sidebar.isHidden == visible {
                    tabs.sidebar.isHidden = !visible
                }
            }
        }
    }

    /// 창의 뿌리에서 자식 쪽으로 내려가며 첫 탭 컨트롤러를 찾는다. 띄운 시트(`presentedViewController`)는
    /// 보지 않는다 — 탭은 그 아래에 있다.
    private static func tabBarController(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tabs = root as? UITabBarController { return tabs }
        for child in root.children {
            if let found = tabBarController(in: child) { return found }
        }
        return nil
    }
}
