// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension TodoItem {

    @nonobjc class func fetchRequest() -> NSFetchRequest<TodoItem> {
        NSFetchRequest<TodoItem>(entityName: "TodoItem")
    }

    @NSManaged var id: UUID

    @NSManaged var title: String

    @NSManaged var detail: String

    @NSManaged var categoryRaw: String

    @NSManaged var dueDate: Date?

    @NSManaged var isDone: Bool

    @NSManaged var repeatsYearly: Bool

    @NSManaged var completedAt: Date?

    @NSManaged var sortIndex: Int

    @NSManaged var createdAt: Date
}
