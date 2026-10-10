import CoreData
import XCTest
@testable import SlowRich

/// **백업 왕복 · 형식 번호 · 못 읽은 칸** (docs/18-stage5-foundation.md 5-5 · 5-6).
///
/// 저장소는 둘 다 인메모리다 — 체험 자료를 채운 쪽에서 백업을 만들고, 빈 쪽으로 되돌린다.
/// 진짜 저장소 · iCloud 에는 닿지 않는다.
@MainActor
final class BackupTests: XCTestCase {

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    /// 체험 자료 → 백업 → 빈 저장소로 되돌림. 엔티티마다 줄 수가 같아야 한다.
    func testRoundTripKeepsEveryEntity() throws {
        let sourceContainer = Persistence.makeTrialContainer()
        let source = sourceContainer.viewContext
        let document = BackupDocument.make(from: source)
        XCTAssertEqual(document.formatVersion, BackupDocument.currentFormat)

        let decoded = try BackupDocument.decode(try document.encoded())
        let targetContainer = Persistence.makeEmptyContainer()
        let target = targetContainer.viewContext
        XCTAssertTrue(BackupDocument.restore(decoded, into: target), "되돌리기 저장 실패: \(Autosave.shared.lastFailure ?? "")")

        // 가구는 되돌릴 때 새로 매단다. 변경 이력은 "백업 되돌리기" 한 줄이 더 붙는다.
        let skipped: Set<String> = ["Household", "ChangeLog"]
        for name in Persistence.managedObjectModel.entities.compactMap(\.name).sorted() where !skipped.contains(name) {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            XCTAssertEqual(try target.count(for: request), try source.count(for: request), "\(name) 줄 수가 다르다")
        }
        let logs = NSFetchRequest<NSManagedObject>(entityName: "ChangeLog")
        XCTAssertGreaterThan(try target.count(for: logs), try source.count(for: logs))

        // 줄 수만이 아니라 값도 — 이름과 주마다의 순자산.
        XCTAssertEqual(Set(target.all(Member.self).map(\.name)), Set(source.all(Member.self).map(\.name)))
        XCTAssertEqual(Set(target.all(Holding.self).map(\.name)), Set(source.all(Holding.self).map(\.name)))
        func worth(_ context: NSManagedObjectContext) -> [Date: Int] {
            Dictionary(context.all(Snapshot.self).map { ($0.weekAnchor, $0.netWorthMinor) }, uniquingKeysWith: max)
        }
        XCTAssertEqual(worth(target), worth(source))
    }

    /// 더 새 판 앱이 만든 백업(형식 2)은 거절한다 — "업데이트하세요" (R6).
    func testNewerFormatIsRefused() throws {
        let sourceContainer = Persistence.makeTrialContainer()
        let source = sourceContainer.viewContext
        var object = try json(try BackupDocument.make(from: source).encoded())
        object["formatVersion"] = BackupDocument.currentFormat + 1
        XCTAssertThrowsError(try BackupDocument.decode(try data(object))) { error in
            XCTAssertEqual(error as? BackupDocument.ReadError, .newerFormat(BackupDocument.currentFormat + 1))
        }
    }

    /// 칸 하나가 빠지면 **그 칸 이름** 을 알려 준다.
    func testMissingFieldIsNamed() throws {
        let sourceContainer = Persistence.makeTrialContainer()
        let source = sourceContainer.viewContext
        var object = try json(try BackupDocument.make(from: source).encoded())
        var members = try XCTUnwrap(object["members"] as? [[String: Any]])
        members[0]["name"] = nil
        object["members"] = members
        XCTAssertThrowsError(try BackupDocument.decode(try data(object))) { error in
            XCTAssertEqual(error as? BackupDocument.ReadError, .field(path: "members[0].name", problem: "칸이 없음"))
        }
    }

    /// 백업이 아닌 파일은 백업이 아니라고만 한다.
    func testNotABackup() {
        for text in ["hello", "[1, 2, 3]", "{\"formatVersion\": \"x\"}"] {
            XCTAssertThrowsError(try BackupDocument.decode(Data(text.utf8)), text) { error in
                XCTAssertEqual(error as? BackupDocument.ReadError, .notBackup, text)
            }
        }
    }
}
