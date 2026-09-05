import Foundation
import Observation

/// 알림에서 앱으로 들어올 때 어느 화면을 열지 전달한다.
///
/// 알림 대리자는 SwiftUI 밖에 있어서 뷰 상태를 직접 못 만진다. 이 객체가 다리다.
@Observable
@MainActor
final class AppRoute {
    static let shared = AppRoute()

    var showReview = false
    /// 알림에서 총액만 기록한 직후 보여줄 안내.
    var totalOnlyMessage: String?

    private init() {}
}
