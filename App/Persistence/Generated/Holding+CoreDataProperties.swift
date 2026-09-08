// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Holding {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Holding> {
        NSFetchRequest<Holding>(entityName: "Holding")
    }

    @NSManaged var id: UUID

    @NSManaged var name: String

    @NSManaged var assetClassRaw: String

    @NSManaged var instrumentTypeRaw: String

    @NSManaged var listingCountryCode: String

    @NSManaged var statusRaw: String

    @NSManaged var cadenceRaw: String

    @NSManaged var valueMinor: Int

    @NSManaged var lastEnteredValueMinor: Int

    @NSManaged var lastEnteredAt: Date?

    @NSManaged var note: String

    /// `Int?` 는 `@NSManaged` 가 직접 못 든다. 저장은 `NSNumber?` 로 하고
    /// KVC 이름만 `targetWeightBP` 로 붙여 준다 — 모델의 칸 이름이 그것이기 때문이다.
    @NSManaged @objc(targetWeightBP) var targetWeightBPNumber: NSNumber?

    /// 쓰는 쪽은 예전 그대로 `Int?` 를 본다.
    var targetWeightBP: Int? {
        get { targetWeightBPNumber?.intValue }
        set { targetWeightBPNumber = newValue.map(NSNumber.init(value:)) }
    }

    @NSManaged var sortIndex: Int

    @NSManaged var createdAt: Date

    @NSManaged var accountID: UUID?

    @NSManaged var account: Account?
}
