import Core
import Foundation
import SwiftData
import UserNotifications

/// 알림 응답 처리. 앱이 꺼져 있어도 총액 한 줄은 남길 수 있어야 한다.
///
/// 대리자 메서드는 어느 액터에도 속하지 않으므로 `self` 를 `@MainActor` 로 넘기면
/// 데이터 경합 위험으로 컴파일이 막힌다. 그래서 실제 처리는 **Sendable 한 값만 받는
/// 정적 메서드**로 뺐다. `@preconcurrency` 로 검사를 끄는 대신 실제로 안전한 형태를 골랐다.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
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
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let container = container   // ModelContainer 는 Sendable 이다
        await MainActor.run {
            Self.handle(action: action, text: typed, container: container)
        }
    }

    @MainActor
    private static func handle(action: String, text: String?, container: ModelContainer) {
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
    private static func recordTotalOnly(_ text: String, container: ModelContainer) {
        let digits = String(text.filter(\.isNumber).prefix(15))
        guard let value = Int(digits), value > 0 else { return }

        let context = ModelContext(container)
        let anchor = ReviewWeek.anchor(for: .now)
        let allSessions = (try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []

        let existing = allSessions.first { $0.weekAnchor == anchor }
        guard existing?.isComplete != true else { return }

        let previous = allSessions
            .filter { $0.completedAt != nil && $0.weekAnchor < anchor }
            .max { $0.weekAnchor < $1.weekAnchor }

        let session = existing ?? ReviewSession(weekAnchor: anchor, totalCount: 0)
        session.isTotalOnly = true
        session.completedAt = .now
        session.totalValueMinor = value
        session.previousTotalValueMinor = previous?.totalValueMinor ?? 0
        if existing == nil { context.insert(session) }

        context.insert(Snapshot(
            weekAnchor: anchor,
            netWorthMinor: value,
            investableMinor: 0,
            liabilitiesMinor: 0
        ))

        try? context.save()

        ReviewNotifications.cancelFollowUp()
        let amount = KoreanAmountFormatter.abbreviated(
            Money(minorUnits: value, currency: .krw), suffix: "원"
        )
        AppRoute.shared.totalOnlyMessage =
            "총액 \(amount)을 기록했습니다. 종목별 내역은 다음 점검 때 채우면 됩니다."
    }
}
