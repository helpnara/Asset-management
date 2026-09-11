import Core
import CoreData
import Foundation

/// **넘긴 순간을 축하한다** (docs/08-feedback.md 88번, C7).
///
/// 로드맵의 자동 마일스톤은 예측이다 — "2028년에 두 배" 라고 적혀 있을 뿐,
/// 실제로 그 주에 넘겼는지는 아무도 말해 주지 않았다. 점검을 끝낼 때 지난 점검과
/// 이번 점검 사이에 **선을 넘었는지** 보고, 넘었으면 변경 이력에 `축하` 로 남긴다.
/// 점검 완료 화면이 그 주의 축하를 보인다. 한 번 넘긴 선은 다시 축하하지 않는다.
@MainActor
enum Celebrations {

    /// 연속 기록에서 축하하는 주차.
    static let streakMarks = [4, 12, 26, 52, 104]

    /// 넘긴 것의 제목들. 이력에도 남긴다.
    @discardableResult
    static func check(previousTotal: Int, newTotal: Int, firstTotal: Int?,
                      targetMinor: Int, streak: Int,
                      in context: NSManagedObjectContext) -> [String] {
        var found: [(subject: String, summary: String)] = []
        let eok = 100_000_000
        let now = Money(minorUnits: newTotal, currency: .krw)

        // 억 단위를 넘겼다. 첫 기록(previous 0)은 넘긴 것이 아니라 시작이다.
        if previousTotal > 0 {
            let before = previousTotal / eok
            let after = newTotal / eok
            if after > before {
                found.append(("\(after)억을 넘었습니다", "총자산 \(KoreanAmountFormatter.compact(now))"))
            }
        }

        // 처음 기록의 두 배.
        if let firstTotal, firstTotal > 0, previousTotal > 0,
           previousTotal < firstTotal * 2, newTotal >= firstTotal * 2 {
            found.append(("처음 기록의 두 배가 됐습니다",
                          "\(KoreanAmountFormatter.compact(Money(minorUnits: firstTotal, currency: .krw))) → \(KoreanAmountFormatter.compact(now))"))
        }

        // 은퇴 목표.
        if targetMinor > 0, previousTotal > 0, previousTotal < targetMinor, newTotal >= targetMinor {
            found.append(("은퇴 목표 금액에 닿았습니다",
                          "목표 \(KoreanAmountFormatter.compact(Money(minorUnits: targetMinor, currency: .krw)))"))
        }

        // 연속 기록.
        if streakMarks.contains(streak) {
            found.append(("\(streak)주 연속 기록", "한 주도 거르지 않았습니다"))
        }

        // 같은 제목이 이미 있으면 다시 남기지 않는다 — 두 번째로 끝낸 사람이
        // 같은 주에 또 넘기거나, 내려갔다 다시 넘긴 경우.
        let existing = Set(context.all(
            ChangeLog.self,
            predicate: NSPredicate(format: "kindRaw == %@", ChangeKind.milestone.rawValue)
        ).map(\.subject))
        var recorded: [String] = []
        for item in found where !existing.contains(item.subject) {
            ChangeLogger.record(.milestone, subject: item.subject, summary: item.summary, in: context)
            recorded.append(item.subject)
        }
        return recorded
    }
}
