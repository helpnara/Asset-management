import Core
import Foundation
import CoreData
import UserNotifications

/// 알림 응답 처리. 앱이 꺼져 있어도 총액 한 줄은 남길 수 있어야 한다.
///
/// 대리자 메서드는 어느 액터에도 속하지 않으므로 `self` 를 `@MainActor` 로 넘기면
/// 데이터 경합 위험으로 컴파일이 막힌다. 그래서 실제 처리는 **Sendable 한 값만 받는
/// 정적 메서드**로 뺐다. `@preconcurrency` 로 검사를 끄는 대신 실제로 안전한 형태를 골랐다.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
        super.init()
    }

    /// 앱이 떠 있을 때도 배너를 띄운다. 토요일 알림은 놓치면 그 주가 빈다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let container = container   // 메인 컨텍스트만 건드린다 — 컨테이너를 async 경계 너머로 넘기지 않는다
        await MainActor.run {
            Self.handle(action: action, category: category, text: typed, container: container)
        }
    }

    @MainActor
    private static func handle(action: String, category: String, text: String?,
                               container: NSPersistentContainer) {
        // 일기 알림을 누르면 현황판 — 카드가 맨 위에 있다. 여기서 가르지 않으면
        // 기본 탭 동작이 주간 점검을 열어 버린다.
        if category == DiaryNotifications.Identifier.category {
            AppRoute.shared.selectedTab = RootView.Tab.dashboard
            return
        }
        // 월간 회고 알림 → 더보기의 회고 화면 (86번).
        if category == RetrospectiveNotifications.category {
            AppRoute.shared.wantsRetrospective = true
            AppRoute.shared.selectedTab = RootView.Tab.more
            return
        }
        switch action {
        case ReviewNotifications.Action.quickTotal:
            if let text { recordTotalOnly(text, container: container) }

        case ReviewNotifications.Action.openReview, UNNotificationDefaultActionIdentifier:
            AppRoute.shared.showReview = true

        default:
            break   // "다음 주에" 는 아무것도 하지 않는다
        }
    }

    /// 총액만 기록한다. 궤적의 점 하나는 남고 구성원별 분해는 비어 있다.
    /// 완벽한 한 주보다 이어지는 스무 주가 낫다 (ADR-0005).
    @MainActor
    private static func recordTotalOnly(_ text: String, container: NSPersistentContainer) {
        let digits = String(text.filter(\.isNumber).prefix(15))
        guard let value = Int(digits), value > 0 else { return }

        let context = container.viewContext
        let anchor = ReviewWeek.anchor(for: .now)
        let allSessions = context.all(ReviewSession.self)

        let existing = allSessions.first { $0.weekAnchor == anchor }
        guard existing?.isComplete != true else { return }

        let previous = allSessions
            .filter { $0.completedAt != nil && $0.weekAnchor < anchor }
            .max { $0.weekAnchor < $1.weekAnchor }

        let session = existing ?? ReviewSession(context: context, weekAnchor: anchor, totalCount: 0)
        session.isTotalOnly = true
        session.completedAt = .now
        session.totalValueMinor = value
        session.previousTotalValueMinor = previous?.totalValueMinor ?? 0

        _ = Snapshot(context: context,
            weekAnchor: anchor,
            netWorthMinor: value,
            investableMinor: 0,
            liabilitiesMinor: 0
        )

        // Autosave 를 거치지 않는 저장이라 매달기·저장소 배정을 직접 부른다 (④).
        // 참가자 폰에서 알림으로 총액만 적으면 그 주 기록이 개인 저장소로 가서
        // 가족에게 안 갔을 것이다.
        Household.attachNew(in: context)
        try? context.save()

        ReviewNotifications.cancelFollowUp()
        let amount = Won.abbreviated(
            Money(minorUnits: value, currency: .krw), suffix: "원"
        )
        AppRoute.shared.totalOnlyMessage =
            "총액 \(amount)을 기록했습니다. 종목별 내역은 다음 점검 때 채우면 됩니다."
    }
}
