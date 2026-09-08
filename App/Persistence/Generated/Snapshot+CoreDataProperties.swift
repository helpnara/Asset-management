// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Snapshot {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Snapshot> {
        NSFetchRequest<Snapshot>(entityName: "Snapshot")
    }

    @NSManaged var id: UUID

    @NSManaged var weekAnchor: Date

    @NSManaged var netWorthMinor: Int

    @NSManaged var investableMinor: Int

    @NSManaged var liabilitiesMinor: Int

    /// 일대다는 `NSSet?` 이다 — `[SnapshotLine]?` 가 아니다.
    /// 정렬해 쓰는 곳에서 풀어 쓴다.
    @NSManaged var lines: NSSet?
}

extension Snapshot {

    @objc(addLinesObject:)
    @NSManaged func addToLines(_ value: SnapshotLine)

    @objc(removeLinesObject:)
    @NSManaged func removeFromLines(_ value: SnapshotLine)

    @objc(addLines:)
    @NSManaged func addToLines(_ values: NSSet)

    @objc(removeLines:)
    @NSManaged func removeFromLines(_ values: NSSet)
}
