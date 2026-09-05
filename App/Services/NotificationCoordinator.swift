import Core
import Foundation
import SwiftData
import UserNotifications

/// 알림 응답 처리. 앱이 꺼져 있어도 총액 한 줄은 남길 수 있어야 한다.
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
        await handle(action: action, text: typed)
    }

    @MainActor
    private func handle(action: String, text: String?) {
        switch action {
        case ReviewNotifications.Action.quickTotal:
            if let text { recordTotalOnly(text) }

        case ReviewNotifications.Action.openReview, UNNotificationDefaultActionIdentifier:
            AppRoute.shared.showReview = true

        default:
            break   // "다음 주에" 는 아무것도 하지 않는다
        }
    }

    /// 총액만 기록한다. 궤적의 점 하나는 남고 구성원별 분해는 비어 있다.
    /// 완벽한 한 주보다 이어지는 스무 주가 낫다 (ADR-0005).
    @MainActor
    private func recordTotalOnly(_ text: String) {
        let digits = String(text.filter(\.isNumber).prefix(15))
        guard let value = Int(digits), value > 0 else { return }

        let context = ModelContext(container)
        let anchor = ReviewWeek.anchor(for: .now)

        let existing = (try? context.fetch(FetchDescriptor<ReviewSession>()))?
            .first { $0.weekAnchor == anchor }
        guard existing?.isComplete != true else { return }

        let previous = (try? context.fetch(FetchDescriptor<ReviewSession>()))?
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
        AppRoute.shared.totalOnlyMessage =
            "총액 \(KoreanAmountFormatter.abbreviated(Money(minorUnits: value, currency: .krw), suffix: "원"))을 기록했습니다. 종목별 내역은 다음 점검 때 채우면 됩니다."
    }
}
