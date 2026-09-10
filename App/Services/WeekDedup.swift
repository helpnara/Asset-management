import CoreData
import Foundation

/// **같은 주의 기록이 둘이면 하나로** (docs/08-feedback.md 96번, A5).
///
/// 두 기기가 오프라인에서 같은 주 점검을 끝내면 `Snapshot`·`ReviewSession` 이
/// 각각 생긴다 — CloudKit 은 유니크 제약이 없다. 그러면 궤적에 한 주에 점이 둘
/// 찍혀 선이 꺾인다. 가구 중복 정리(`Household.pruneEmptyLocalDuplicates`)와
/// 같은 자리에서, 가져오기가 끝난 뒤에 주차별로 하나만 남긴다.
///
/// 어느 것을 남기나. 스냅샷은 **구성원 줄이 있는 것**, 같으면 id 가 큰 것 —
/// 두 기기 다 같은 종목값에서 계산한 총액이라 어느 쪽이든 실질적 차이는 없다.
/// 세션은 나중에 끝낸 것을 남기고 적은 구성원은 합친다.
@MainActor
enum WeekDedup {

    @discardableResult
    static func run(in context: NSManagedObjectContext) -> Int {
        var removed = 0

        let snapshots = context.all(Snapshot.self)
        for (_, group) in Dictionary(grouping: snapshots, by: \.weekAnchor) where group.count > 1 {
            guard let keep = group.max(by: { lhs, rhs in
                (lhs.sortedLines.count, lhs.id.uuidString) < (rhs.sortedLines.count, rhs.id.uuidString)
            }) else { continue }
            for snapshot in group where snapshot != keep {
                context.delete(snapshot)
                removed += 1
            }
        }

        let sessions = context.all(ReviewSession.self)
        for (_, group) in Dictionary(grouping: sessions, by: \.weekAnchor) where group.count > 1 {
            guard let keep = group.max(by: { lhs, rhs in
                (lhs.completedAt ?? .distantPast, lhs.enteredCount, lhs.id.uuidString)
                    < (rhs.completedAt ?? .distantPast, rhs.enteredCount, rhs.id.uuidString)
            }) else { continue }
            var entered = keep.enteredMemberIDSet
            for session in group where session != keep {
                entered.formUnion(session.enteredMemberIDSet)
                keep.enteredCount = max(keep.enteredCount, session.enteredCount)
                context.delete(session)
                removed += 1
            }
            keep.setEnteredMembers(entered)
        }

        if removed > 0 {
            ChangeLogger.record(.other, subject: "같은 주 기록 정리",
                                summary: "두 기기가 같은 주에 남긴 기록 \(removed)건을 하나로 합쳤습니다",
                                in: context)
        }
        return removed
    }
}
