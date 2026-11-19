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
        // 같은 주는 시간대가 달라도 같은 토요일 (194번 D3).
        let range = ReviewWeek.nearbyRange(of: weekAnchor)
        let existing = Dictionary(
            context.all(HoldingRecord.self,
                        predicate: NSPredicate(format: "weekAnchor > %@ AND weekAnchor < %@",
                                               range.lower as NSDate, range.upper as NSDate))
                .filter { ReviewWeek.isSameWeek($0.weekAnchor, weekAnchor) }
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
        // 같은 주가 둘이면(두 기기가 같은 주에 끝냄) 하나만. **날 번호로** 가린다 (199번 B3) — 시간대가
        // 다른 두 기기의 기준일은 시각이 몇 시간 달라 `Set<Date>` 로는 같은 주가 점 둘로 그려졌다.
        var seen: Set<Int> = []
        return Array(newestFirst.filter { seen.insert(ReviewWeek.dayKey($0.weekAnchor)).inserted }.reversed())
    }

    /// **그 주에 많이 움직인 종목** (219번 E). 그 주의 기록과 **그 앞 마지막 점검**의 기록을 견준다 —
    /// 한 주를 걸렀으면 2주 치 변화다(화면에 견준 날짜를 적는다). 지난 점검을 다시 열어도 그때 기준.
    /// `liabilityIDs` 는 부채 계좌의 종목 — 부호를 뒤집어 갚은 만큼이 오른 쪽에 서게 한다.
    @MainActor
    static func movers(weekAnchor: Date, liabilityIDs: Set<UUID>, in context: NSManagedObjectContext,
                       limit: Int = 3) -> (result: WeeklyMovers.Result, since: Date)? {
        let range = ReviewWeek.nearbyRange(of: weekAnchor)
        let thisWeek = context.all(
            HoldingRecord.self,
            predicate: NSPredicate(format: "weekAnchor > %@ AND weekAnchor < %@",
                                   range.lower as NSDate, range.upper as NSDate))
            .filter { ReviewWeek.isSameWeek($0.weekAnchor, weekAnchor) }
        guard !thisWeek.isEmpty,
              let since = context.all(
                HoldingRecord.self,
                sortedBy: [NSSortDescriptor(key: "weekAnchor", ascending: false)],
                predicate: NSPredicate(format: "weekAnchor < %@", range.lower as NSDate),
                limit: 1).first?.weekAnchor
        else { return nil }
        let before = ReviewWeek.nearbyRange(of: since)
        let lastWeek = context.all(
            HoldingRecord.self,
            predicate: NSPredicate(format: "weekAnchor > %@ AND weekAnchor < %@",
                                   before.lower as NSDate, before.upper as NSDate))
            .filter { ReviewWeek.isSameWeek($0.weekAnchor, since) }

        func signed(_ record: HoldingRecord) -> Money {
            let value = liabilityIDs.contains(record.holdingID) ? -record.valueMinor : record.valueMinor
            return Money(minorUnits: value, currency: .krw)
        }
        // 같은 주가 두 기기에서 끝나 같은 종목이 둘이면 하나만.
        var seen: Set<UUID> = []
        let current: [WeeklyMovers.Entry] = thisWeek.compactMap { record in
            guard seen.insert(record.holdingID).inserted else { return nil }
            return .init(id: record.holdingID,
                         name: record.holdingName.isEmpty ? "이름 없음" : record.holdingName,
                         detail: record.accountName, value: signed(record))
        }
        let previous = Dictionary(lastWeek.map { ($0.holdingID, signed($0)) },
                                  uniquingKeysWith: { first, _ in first })
        return (WeeklyMovers.top(current: current, previous: previous, limit: limit), since)
    }
}
