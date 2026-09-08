// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Member {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Member> {
        NSFetchRequest<Member>(entityName: "Member")
    }

    @NSManaged var id: UUID

    @NSManaged var name: String

    @NSManaged var roleNote: String

    @NSManaged var birthYear: Int

    @NSManaged var birthMonth: Int

    @NSManaged var taxResidencyRaw: String

    @NSManaged var targetRetirementAge: Int

    @NSManaged var monthlyContributionMinor: Int

    @NSManaged var employerMatchMinor: Int

    @NSManaged var note: String

    @NSManaged var colorIndex: Int

    @NSManaged var sortIndex: Int

    @NSManaged var createdAt: Date

    /// 일대다는 `NSSet?` 이다 — `[Account]?` 가 아니다.
    /// 정렬해 쓰는 곳에서 풀어 쓴다.
    @NSManaged var accounts: NSSet?
}

extension Member {

    @objc(addAccountsObject:)
    @NSManaged func addToAccounts(_ value: Account)

    @objc(removeAccountsObject:)
    @NSManaged func removeFromAccounts(_ value: Account)

    @objc(addAccounts:)
    @NSManaged func addToAccounts(_ values: NSSet)

    @objc(removeAccounts:)
    @NSManaged func removeFromAccounts(_ values: NSSet)
}
