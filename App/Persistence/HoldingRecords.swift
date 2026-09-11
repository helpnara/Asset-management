import Core
import CoreData
import Foundation

/// 종목별 주간 값 (A3). 쓰는 길은 `record(...)` 하나, 읽는 길은 `history(...)` 하나.
extension HoldingRecord {

    /// **점검을 끝낼 때 종목마다 한 줄.** 같은 주에 다시 끝내면(이어서 끝낸
    /// 가족, 다시 열기) 그 줄을 갱신한다 — 같은 종목·같은 주가 둘이 되지 않게.
    /// 고정 종목도 남긴다: "안 변했다" 도 기록이다.
    @MainActor
    static func record(members: [Member], weekAnchor: Date, in context: NSManagedObjectContext) {
        let existing = Dictionary(
            context.all(HoldingRecord.self,
                        predicate: NSPredicate(format: "weekAnchor == %@", weekAnchor as NSDate))
                .map { ($0.holdingID, $0) },
            uniquingKeysWith: { first, _ in first })

        for member in members {
            for account in member.sortedAccounts where !account.isArchived {
                for holding in account.sortedHoldings {
                    let line = existing[holding.id] ?? {
                        let line = HoldingRecord(context: context)
                        line.weekAnchor = weekAnchor
                        line.holdingID = holding.id
                        return line
                    }()
                    line.holdingName = holding.name
                    line.accountName = account.name
                    line.memberID = member.id
                    line.valueMinor = holding.valueMinor
                }
            }
        }
    }

    /// 한 종목의 지난 값들, **오래된 주가 앞**. 최근 `limit` 주만.
    static func history(of holdingID: UUID, in context: NSManagedObjectContext,
                        limit: Int = 26) -> [HoldingRecord] {
        let newestFirst = context.all(
            HoldingRecord.self,
            sortedBy: [NSSortDescriptor(key: "weekAnchor", ascending: false)],
            predicate: NSPredicate(format: "holdingID == %@", holdingID as CVarArg),
            limit: limit)
        // 같은 주가 둘이면(두 기기가 같은 주에 끝냄) 하나만.
        var seen: Set<Date> = []
        return Array(newestFirst.filter { seen.insert($0.weekAnchor).inserted }.reversed())
    }
}
