import Core
import CoreData
import Foundation

/// **이번 주 요약을 종목값에서 다시 맞춘다** (docs/08-feedback.md 193번 B).
///
/// 10-03 토요일, 아빠 폰과 엄마 폰이 같은 주 점검을 **동시에 이어서 끝냈다.**
/// 둘은 같은 세션 · 스냅샷 하나를 각자 고쳤고, 동기화는 칸마다 **늦게 쓴 쪽**을
/// 남긴다(`mergeByPropertyStoreTrump`). 그날은 운 좋게 맞았지만 구조상 이렇게
/// 어긋날 수 있다.
///
///  · `적은 구성원` — 한 칸짜리 글이라 늦은 쪽이 앞사람 몫을 지운다 → 연속이 끊긴다
///  · 스냅샷 총액 — 상대의 새 종목값을 받기 전에 계산해 늦게 쓰면 지난 값이 남는다
///  · 구성원 줄 · 종목별 값 — 서로 모르는 줄이 두 벌 남을 수 있다
///
/// 종목값은 종목마다 한 사람만 고치므로 어긋나지 않는다. 그래서 **요약을 종목값이라는
/// 한 출처에서 다시 계산**하면, 누가 늦게 썼든 두 기기가 같은 답에 닿는다.
///
/// **지킬 것.**
///  · 이번 주만. 지난 주는 그 주의 기록이다 — 지금 값으로 덮으면 역사가 바뀐다.
///  · 끝낸 점검이 있을 때만. 없는 세션 · 스냅샷을 만들지 않는다 — 그건 점검의 일이다.
///  · 알림으로 총액만 적은 주(`isTotalOnly`)는 사람이 친 총액이 답이라 건드리지 않는다.
///  · **값이 다를 때만 쓴다.** 같으면 안 쓴다 — 두 기기가 서로 덮어쓰며 핑퐁하지 않게.
///  · 지울 것을 고를 때는 **id 가 가장 작은 것을 남긴다.** 두 기기가 따로 골라도 같은
///    것을 남겨야 한쪽이 지운 것을 다른 쪽이 되살리지 않는다.
///  · `적은 구성원` 은 **더하기만** 한다. 종목의 `적은 시각` 으로 센 사람을 보탤 뿐
///    빼지 않는다 — 점검이 센 것과 여기서 센 것이 달라도 앞사람 몫이 사라지지 않게.
///
/// 이번 주 안에서는 기록이 **지금 종목값을 따른다** — 점검 뒤 자산 탭에서 값을 고쳐도
/// 다음 동기화에 이번 주 점이 따라온다. 현황판 총자산과 지난 기록 맨 위 줄이 같은 말을
/// 하는 것이 맞다(193번 사용자 확인 2 가 바로 그 대조였다).
@MainActor
enum ThisWeekReconcile {

    /// 고친 것이 있으면 `true`.
    @discardableResult
    static func run(in context: NSManagedObjectContext, now: Date = .now) -> Bool {
        let anchor = ReviewWeek.anchor(for: now)
        let anchorPredicate = NSPredicate(format: "weekAnchor == %@", anchor as NSDate)

        let sessions = context.all(ReviewSession.self, predicate: anchorPredicate)
        // 같은 주가 둘이면 `WeekDedup` 이 먼저 하나로 만든다. 여기서는 남을 것 하나만 본다.
        guard sessions.count == 1, let session = sessions.first,
              session.isComplete, !session.isTotalOnly else { return false }
        let snapshots = context.all(Snapshot.self, predicate: anchorPredicate)
        guard snapshots.count == 1, let snapshot = snapshots.first else { return false }

        let members = context.all(Member.self, sortedBy: [NSSortDescriptor(key: "sortIndex", ascending: true)])
        let holdings = members.flatMap(\.sortedAccounts).flatMap(\.sortedHoldings)
        let rollup = Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
        var changed = false

        // 1) 세션 — 총액과 적은 구성원.
        if session.totalValueMinor != rollup.netWorth.minorUnits {
            session.totalValueMinor = rollup.netWorth.minorUnits
            changed = true
        }
        let asked = holdings.filter { $0.isDue(asOf: now) || $0.wasEntered(thisWeekOf: now) }
        let enteredCount = asked.filter { $0.wasEntered(thisWeekOf: now) }.count
        if enteredCount > session.enteredCount {
            session.enteredCount = enteredCount
            changed = true
        }
        var entered = session.enteredMemberIDSet
        for member in members {
            let mine = member.sortedAccounts.flatMap(\.sortedHoldings)
                .filter { $0.isDue(asOf: now) || $0.wasEntered(thisWeekOf: now) }
            // 묻는 종목이 없는 사람은 세지 않는다 — 점검은 그런 사람을 "적음" 으로 치지만,
            // 여기서 보태면 아무도 안 끝낸 사람까지 들어간다. 점검이 이미 넣었으면 남는다.
            if !mine.isEmpty, mine.allSatisfy({ $0.wasEntered(thisWeekOf: now) }) {
                entered.insert(member.id)
            }
        }
        if entered != session.enteredMemberIDSet {
            session.setEnteredMembers(entered)
            changed = true
        }

        // 2) 스냅샷 — 총액 셋.
        if snapshot.netWorthMinor != rollup.netWorth.minorUnits {
            snapshot.netWorthMinor = rollup.netWorth.minorUnits
            changed = true
        }
        if snapshot.investableMinor != rollup.investable.minorUnits {
            snapshot.investableMinor = rollup.investable.minorUnits
            changed = true
        }
        if snapshot.liabilitiesMinor != rollup.liabilities.minorUnits {
            snapshot.liabilitiesMinor = rollup.liabilities.minorUnits
            changed = true
        }

        // 3) 구성원 줄 — 사람마다 하나. 지우고 새로 넣지 않고 **있는 것을 고친다**
        //    (새로 넣으면 두 기기가 각자 넣은 줄이 또 두 벌이 된다).
        //    줄이 하나도 없는 스냅샷(옛 기록 · 지난 기록 직접 입력)은 점검이 안 남긴 것이라 둔다.
        let lines = snapshot.sortedLines
        if !lines.isEmpty {
            let byMember = Dictionary(grouping: lines, by: \.memberID)
            for (position, member) in members.enumerated() {
                let value = (rollup.byMember[member.id] ?? .zero(.krw)).minorUnits
                let group = (byMember[member.id] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
                if let keep = group.first {
                    for extra in group.dropFirst() {
                        context.delete(extra)
                        changed = true
                    }
                    if keep.valueMinor != value { keep.valueMinor = value; changed = true }
                    if keep.memberName != member.name { keep.memberName = member.name; changed = true }
                    if keep.sortIndex != position { keep.sortIndex = position; changed = true }
                } else {
                    let line = SnapshotLine(context: context, memberID: member.id, memberName: member.name,
                                            valueMinor: value, sortIndex: position)
                    line.snapshot = snapshot
                    changed = true
                }
            }
        }

        // 4) 종목별 값 (A3) — 이번 주 줄만. 있는 줄을 고치고 겹친 줄은 하나로.
        let records = context.all(HoldingRecord.self, predicate: anchorPredicate)
        let valueByHolding = Dictionary(holdings.map { ($0.id, $0.valueMinor) },
                                        uniquingKeysWith: { first, _ in first })
        for (holdingID, group) in Dictionary(grouping: records, by: \.holdingID) {
            let ordered = group.sorted { $0.id.uuidString < $1.id.uuidString }
            for extra in ordered.dropFirst() {
                context.delete(extra)
                changed = true
            }
            if let keep = ordered.first, let value = valueByHolding[holdingID], keep.valueMinor != value {
                keep.valueMinor = value
                changed = true
            }
        }

        return changed
    }
}
