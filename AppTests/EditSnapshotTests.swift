import CoreData
import XCTest
@testable import SlowRich

/// **편집 취소는 이 기기에서 고친 칸만 되돌린다** (194번 E1 · docs/18 5-6) — 10-10 두 폰으로
/// 손으로 확인한 것(체크리스트 9)을 인메모리 저장소로 매번 확인한다.
@MainActor
final class EditSnapshotTests: XCTestCase {

    func testCancelKeepsWhatAnotherDeviceChanged() async throws {
        let container = Persistence.makeEmptyContainer()
        let context = container.viewContext
        let holding = Holding(context: context, name: "원래 이름")
        holding.note = "원래 메모"
        try context.save()

        // 편집 시트를 연다.
        let snapshot = EditSnapshot(of: holding)

        // 다른 기기의 고침이 iCloud 로 들어와 합쳐진다 — 같은 저장소의 다른 컨텍스트에서
        // 저장하면 화면 컨텍스트가 스스로 합친다(`automaticallyMergesChangesFromParent`).
        // 주 큐 컨텍스트라 `perform` 없이 이 자리에서 쓴다 (행위자 경계를 넘지 않게).
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = container.persistentStoreCoordinator
        let remote = try XCTUnwrap(other.object(with: holding.objectID) as? Holding)
        remote.name = "가족이 고친 이름"
        try other.save()
        for _ in 0..<40 where holding.name != "가족이 고친 이름" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(holding.name, "가족이 고친 이름", "합치기가 화면 컨텍스트에 닿지 않았다")

        // 이 기기에서 다른 칸을 고쳐 저장한다 (자동 저장과 같은 길).
        holding.note = "이 기기에서 고친 메모"
        try context.save()

        snapshot.restore(to: holding)

        XCTAssertEqual(holding.note, "원래 메모", "이 기기에서 고친 칸은 되돌린다")
        XCTAssertEqual(holding.name, "가족이 고친 이름", "가족이 고친 칸은 남긴다")
    }

    /// 아직 저장 안 된 마지막 고침도 되돌린다.
    func testCancelRevertsUnsavedEdit() throws {
        let container = Persistence.makeEmptyContainer()
        let context = container.viewContext
        let holding = Holding(context: context, name: "원래 이름")
        try context.save()
        let snapshot = EditSnapshot(of: holding)
        holding.name = "저장 전 고침"
        snapshot.restore(to: holding)
        XCTAssertEqual(holding.name, "원래 이름")
    }
}
