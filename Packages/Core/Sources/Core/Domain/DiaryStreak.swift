import Foundation

/// 목·실·감 일기의 **연속 일수** (docs/05-roadmap.md 마지막 묶음 1).
///
/// 주간 점검의 `ReviewWeek.streak` 과 같은 태도다 — 오늘 아직 안 적었다고
/// 0 으로 만들지 않는다. 어제까지 이어져 있으면 그 수를 그대로 보여 주고,
/// 오늘 적으면 하나 늘어난다. 하루라도 비면 거기서 끊긴다.
public enum DiaryStreak {

    /// - Parameter days: 글이 있는 날들. 시각이 섞여 있어도 된다 — 자정으로 맞춰 센다.
    public static func count(days: [Date], asOf: Date, calendar: Calendar = .current) -> Int {
        let written = Set(days.map { calendar.startOfDay(for: $0) })
        guard !written.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: asOf)
        var cursor = written.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)

        var count = 0
        while written.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
