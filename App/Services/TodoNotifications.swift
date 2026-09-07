import Foundation
import UserNotifications

/// 기한 알림.
///
/// 주간 점검 알림과 **따로 건다.** 토요일 알림은 "숫자를 적는" 행동을 부르고
/// 이건 "기한이 왔다"를 알린다. 둘을 한 알림에 섞으면 둘 다 무시하게 된다.
///
/// 앱이 뜰 때마다, 그리고 할 일을 고칠 때마다 통째로 다시 건다.
/// 개별 취소·갱신을 추적하면 어긋나는 자리가 생긴다.
enum TodoNotifications {

    private static let prefix = "todo-"
    private static let maturityPrefix = "maturity-"

    /// 액터 경계를 건너는 입력. `@Model` 은 `Sendable` 이 아니므로 값만 뽑아 넘긴다
    /// (CLAUDE.md 규칙).
    struct Input: Sendable {
        struct Item: Sendable {
            var id: UUID
            var title: String
            var dueDate: Date
            var repeatsYearly: Bool
        }
        var items: [Item]
        /// 계좌 만기 (docs/08-feedback.md 28번). 할 일과 같은 길을 타되
        /// **미리** 알린다 — 만기 당일에 알아도 할 수 있는 것이 없다.
        var maturities: [Item]

        @MainActor
        init(items: [TodoItem], accounts: [Account]) {
            self.items = items.compactMap { item in
                guard !item.isDone, let due = item.dueDate else { return nil }
                return Item(id: item.id,
                            title: item.title.isEmpty ? "할 일" : item.title,
                            dueDate: due,
                            repeatsYearly: item.repeatsYearly)
            }

            let calendar = Calendar.current
            self.maturities = accounts.compactMap { account in
                guard !account.isArchived, let matures = account.maturesOn else { return nil }
                // 30일 전에 알린다. 이미 30일 안이면 만기 당일에라도 알린다.
                let early = calendar.date(byAdding: .day, value: -30, to: matures) ?? matures
                let fireDate = early > .now ? early : matures
                guard fireDate > .now else { return nil }
                let owner = account.owner?.name ?? ""
                let name = account.name.isEmpty ? account.kind.label : account.name
                return Item(id: account.id,
                            title: owner.isEmpty ? name : "\(owner) · \(name)",
                            dueDate: fireDate,
                            repeatsYearly: false)
            }
        }
    }

    static func refresh(_ input: Input) async {
        let center = UNUserNotificationCenter.current()
        guard await ReviewNotifications.authorizationStatus() != .denied else { return }

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) || $0.hasPrefix(maturityPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        let calendar = Calendar.current
        for item in input.items {
            // 지난 기한에는 걸지 않는다. 해마다 되돌아오는 것만 다음 해로 민다.
            var due = item.dueDate
            if due < .now {
                guard item.repeatsYearly,
                      let next = calendar.date(byAdding: .year, value: 1, to: due),
                      next > .now
                else { continue }
                due = next
            }

            let content = UNMutableNotificationContent()
            content.title = "오늘까지 — \(item.title)"
            content.body = "더보기 → 유의사항 · 할 일에서 확인하세요."
            content.sound = .default

            var components = calendar.dateComponents([.year, .month, .day], from: due)
            components.hour = 9
            components.minute = 0

            let request = UNNotificationRequest(
                identifier: prefix + item.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }

        for item in input.maturities {
            let content = UNMutableNotificationContent()
            content.title = "만기가 다가옵니다 — \(item.title)"
            content.body = "연장할지 옮길지 정해 두세요. 자산 탭에서 계좌를 열면 날짜가 보입니다."
            content.sound = .default

            var components = calendar.dateComponents([.year, .month, .day], from: item.dueDate)
            components.hour = 9
            components.minute = 0

            let request = UNNotificationRequest(
                identifier: maturityPrefix + item.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
