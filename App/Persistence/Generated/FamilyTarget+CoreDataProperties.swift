// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension FamilyTarget {

    @nonobjc class func fetchRequest() -> NSFetchRequest<FamilyTarget> {
        NSFetchRequest<FamilyTarget>(entityName: "FamilyTarget")
    }

    @NSManaged var id: UUID

    /// `Dimension.rawValue`. 지역인지 자산군인지.
    @NSManaged var dimensionRaw: String

    /// 그 축 안에서의 키 — `Region.rawValue` 또는 `AssetClass.rawValue`.
    @NSManaged var key: String

    @NSManaged var targetBP: Int
}
