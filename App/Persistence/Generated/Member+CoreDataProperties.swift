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

    /// 이 사람 몫의 월 적립액. 계획 탭에서 "구성원별로 나눠 넣기"를 켰을 때만 쓴다.
    @NSManaged var monthlyContributionMinor: Int

    /// 회사가 넣어 주는 몫. `monthlyContributionMinor` 는 **본인 부담**이라는
    /// 뜻 그대로 두었으므로 이미 적어 둔 값을 고칠 필요가 없다.
    ///
    /// 궤적에는 합계가 쓰이고, **저축률 진단에는 본인 부담만** 쓴다 —
    /// 회사가 넣어 주는 돈을 내 저축으로 세면 저축률이 부풀려진다
    /// (docs/08-feedback.md 10번).
    @NSManaged var employerMatchMinor: Int

    /// 그 사람에게만 걸리는 한도·재검토 시점. 1페이지 구성원 카드의 `※` 줄.
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
