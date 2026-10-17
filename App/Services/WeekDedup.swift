import Core
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
///
/// **세션도 스냅샷과 같은 쪽을 남긴다** (194번 E9). 한 사람은 알림으로 총액만,
/// 다른 사람은 전체 점검을 끝내면 — 스냅샷은 구성원 줄이 있는 전체 점검 것이
/// 남는데 세션은 "늦게 끝낸 것" 이라 총액만 적은 것이 남을 수 있었다. 두 총액이
/// 다르고, 남은 세션이 `총액만` 이라 이번 주 맞추기(`ThisWeekReconcile`)도 건너뛰어
/// 어긋남이 굳었다. 그래서 **전체 점검 세션을 먼저**, 그다음 늦게 끝낸 것.
@MainActor
enum WeekDedup {

    @discardableResult
    static func run(in context: NSManagedObjectContext) -> Int {
        var removed = 0

        let snapshots = context.all(Snapshot.self)
        // 같은 주는 날로 묶는다 — 기기 시간대가 달라도 같은 토요일이면 한 주 (194번 D3).
        for (_, group) in Dictionary(grouping: snapshots, by: { ReviewWeek.dayKey($0.weekAnchor) }) where group.count > 1 {
            // **모든 기기가 같은 쪽을 남기게** (199번 A6). 각 기기가 다른 쪽을 지우면 둘 다 사라진다.
            // 그래서 기기마다 다를 수 있는 것(줄 "수" — 가져오다 만 기기는 적게 센다 · 가져온 순서)은
            // 쓰지 않는다. 줄이 "있나" 만 보고, 그다음 id, 그다음 CloudKit 레코드 이름 — 백업 되돌리기
            // 뒤 옛 사본이 되살아나 id 까지 같을 때도 갈린다.
            guard let keep = group.max(by: { lhs, rhs in
                (lhs.sortedLines.isEmpty ? 0 : 1, lhs.id.uuidString, recordName(lhs))
                    < (rhs.sortedLines.isEmpty ? 0 : 1, rhs.id.uuidString, recordName(rhs))
            }) else { continue }
            for snapshot in group where snapshot != keep {
                context.delete(snapshot)
                removed += 1
            }
        }

        let sessions = context.all(ReviewSession.self)
        for (_, group) in Dictionary(grouping: sessions, by: { ReviewWeek.dayKey($0.weekAnchor) }) where group.count > 1 {
            guard let keep = group.max(by: { lhs, rhs in
                let left = (lhs.isTotalOnly ? 0 : 1, lhs.completedAt ?? .distantPast)
                let right = (rhs.isTotalOnly ? 0 : 1, rhs.completedAt ?? .distantPast)
                if left != right { return left < right }
                return (lhs.enteredCount, lhs.id.uuidString, recordName(lhs))
                    < (rhs.enteredCount, rhs.id.uuidString, recordName(rhs))
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

    /// CloudKit 레코드 이름 — 같은 레코드면 어느 기기에서나 같다. 아직 안 올라간 것은 빈 글자 (199번 A6).
    static func recordName(_ object: NSManagedObject) -> String {
        (Persistence.container as? NSPersistentCloudKitContainer)?
            .recordID(for: object.objectID)?.recordName ?? ""
    }
}
