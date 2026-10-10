import Core
import CoreData
import XCTest
@testable import SlowRich

/// **같은 주 정리** (194번 E9 · docs/18 5-6) — 10-10 두 폰으로 손으로 확인한 것(체크리스트 10)을
/// 인메모리 저장소로 매번 확인한다.
@MainActor
final class WeekDedupTests: XCTestCase {

    /// 한 사람은 알림으로 총액만, 다른 사람은 전체 점검. 총액만 적은 것이 **나중에** 끝났어도
    /// 전체 점검 세션과 구성원 줄이 있는 스냅샷이 남는다.
    func testFullReviewWinsOverTotalOnly() throws {
        let container = Persistence.makeEmptyContainer()
        let context = container.viewContext
        let anchor = ReviewWeek.anchor(for: .now)

        let full = ReviewSession(context: context, weekAnchor: anchor, totalCount: 3)
        full.completedAt = Date.now.addingTimeInterval(-600)
        full.totalValueMinor = 200
        full.enteredCount = 3

        let totalOnly = ReviewSession(context: context, weekAnchor: anchor.addingTimeInterval(3_600), totalCount: 0)
        totalOnly.isTotalOnly = true
        totalOnly.completedAt = .now
        totalOnly.totalValueMinor = 100

        let detailed = Snapshot(context: context, weekAnchor: anchor, netWorthMinor: 200,
                                investableMinor: 200, liabilitiesMinor: 0)
        let line = SnapshotLine(context: context, memberID: UUID(), memberName: "가", valueMinor: 200, sortIndex: 0)
        line.snapshot = detailed
        _ = Snapshot(context: context, weekAnchor: anchor.addingTimeInterval(3_600), netWorthMinor: 100,
                     investableMinor: 100, liabilitiesMinor: 0)
        try context.save()

        XCTAssertEqual(WeekDedup.run(in: context), 2)
        try context.save()

        let sessions = context.all(ReviewSession.self)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.isTotalOnly, false)
        XCTAssertEqual(sessions.first?.totalValueMinor, 200)

        let snapshots = context.all(Snapshot.self)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.netWorthMinor, 200)
    }

    /// 다른 주는 건드리지 않는다.
    func testDifferentWeeksStay() throws {
        let container = Persistence.makeEmptyContainer()
        let context = container.viewContext
        let anchor = ReviewWeek.anchor(for: .now)
        for week in 0..<3 {
            let session = ReviewSession(context: context, weekAnchor: anchor.addingTimeInterval(Double(-week) * 7 * 86_400),
                                        totalCount: 1)
            session.completedAt = .now
        }
        try context.save()
        XCTAssertEqual(WeekDedup.run(in: context), 0)
        XCTAssertEqual(context.all(ReviewSession.self).count, 3)
    }
}
