// **이 파일은 이제 손으로 고친다.** 예전에는 생성물이었다.
//
// 4차 1b-2 로 `@Model` 이 사라지면서 원본이 `App/SlowRich.xcdatamodeld` 가
// 됐다. 그런데 모델 파일에는 주석 칸이 없다 — 아래 `///` 들은 "왜 이 칸이
// 있나" 를 적어 둔 이 저장소의 자산인데, 모델에서 다시 뽑으면 **전부
// 날아간다.** 그래서 `generate-managed-classes.py` 는 더 돌리지 않는다
// (돌리면 스스로 막는다).
//
// 칸을 더할 때는 **셋을 함께** 고친다:
//   App/SlowRich.xcdatamodeld · 이 파일 · Tools/cloudkit/slowrich.ckdb
// CI 가 서로 대조하므로 하나만 고치면 빌드가 막힌다.

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
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

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
