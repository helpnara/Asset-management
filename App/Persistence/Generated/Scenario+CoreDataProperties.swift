// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Scenario {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Scenario> {
        NSFetchRequest<Scenario>(entityName: "Scenario")
    }

    @NSManaged var id: UUID

    @NSManaged var name: String

    @NSManaged var monthlyMinor: Int

    @NSManaged var retirementYear: Int

    @NSManaged var returnBP: Int

    @NSManaged var volatilityBP: Int

    /// 저장할 때의 은퇴 시점 예상. 목록에서 비교할 때 쓴다.
    @NSManaged var projectedMinor: Int

    @NSManaged var createdAt: Date
}
