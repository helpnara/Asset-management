// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Principle {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Principle> {
        NSFetchRequest<Principle>(entityName: "Principle")
    }

    @NSManaged var id: UUID

    /// 1페이지에 붙는 번호. 1부터.
    @NSManaged var order: Int

    @NSManaged var title: String

    @NSManaged var detail: String

    /// 점검 주기 메모 — `분기 1회` 처럼 자유롭게 적는다.
    @NSManaged var reviewNote: String

    @NSManaged var createdAt: Date
}
