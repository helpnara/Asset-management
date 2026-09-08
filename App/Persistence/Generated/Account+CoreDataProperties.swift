// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Account {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Account> {
        NSFetchRequest<Account>(entityName: "Account")
    }

    @NSManaged var id: UUID

    @NSManaged var name: String

    @NSManaged var institution: String

    @NSManaged var kindRaw: String

    @NSManaged var isArchived: Bool

    @NSManaged var sortIndex: Int

    @NSManaged var createdAt: Date

    @NSManaged var annualContributionMinor: Int

    @NSManaged var annualLimitMinor: Int

    /// `Int?` 는 `@NSManaged` 가 직접 못 든다. 저장은 `NSNumber?` 로 하고
    /// KVC 이름만 `expectedReturnBP` 로 붙여 준다 — 모델의 칸 이름이 그것이기 때문이다.
    @NSManaged @objc(expectedReturnBP) var expectedReturnBPNumber: NSNumber?

    /// 쓰는 쪽은 예전 그대로 `Int?` 를 본다.
    var expectedReturnBP: Int? {
        get { expectedReturnBPNumber?.intValue }
        set { expectedReturnBPNumber = newValue.map(NSNumber.init(value:)) }
    }

    @NSManaged var maturesOn: Date?

    @NSManaged var ownerID: UUID?

    /// 일대다는 `NSSet?` 이다 — `[Holding]?` 가 아니다.
    /// 정렬해 쓰는 곳에서 풀어 쓴다.
    @NSManaged var holdings: NSSet?

    @NSManaged var owner: Member?
}

extension Account {

    @objc(addHoldingsObject:)
    @NSManaged func addToHoldings(_ value: Holding)

    @objc(removeHoldingsObject:)
    @NSManaged func removeFromHoldings(_ value: Holding)

    @objc(addHoldings:)
    @NSManaged func addToHoldings(_ values: NSSet)

    @objc(removeHoldings:)
    @NSManaged func removeFromHoldings(_ values: NSSet)
}
