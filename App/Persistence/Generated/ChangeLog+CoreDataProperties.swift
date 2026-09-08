// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension ChangeLog {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChangeLog> {
        NSFetchRequest<ChangeLog>(entityName: "ChangeLog")
    }

    @NSManaged var id: UUID

    @NSManaged var at: Date

    @NSManaged var actor: String

    @NSManaged var kindRaw: String

    @NSManaged var subject: String

    @NSManaged var summary: String
}
