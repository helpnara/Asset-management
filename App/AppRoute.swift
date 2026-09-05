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
    /// 현황판 빈 상태에서 "구성원 추가"를 누르면 자산 탭으로 보낸다.
    /// 탭 선택을 RootView 의 `@State` 로만 두면 다른 화면에서 바꿀 길이 없다.
    var selectedTab = RootView.initialTab
    /// 현황판의 [구성원 추가하기] 는 탭만 바꾸는 게 아니라 편집 시트까지 연다.
    /// 탭으로 보내 놓고 다시 + 를 찾게 하면 "다음 한 걸음"이 두 걸음이 된다.
    var wantsNewMember = false
    /// 알림에서 총액만 기록한 직후 보여줄 안내.
    var totalOnlyMessage: String?

    private init() {}
}
