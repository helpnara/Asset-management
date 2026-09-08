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

    /// 올해 이 계좌에 넣은 금액. 사용자가 직접 적는다 (ADR-0005 — 가져오지 않는다).
    @NSManaged var annualContributionMinor: Int

    /// 연간 납입 한도. 0이면 진단에서 판단하지 않는다.
    ///
    /// **앱은 세법을 따라가지 않는다.** 한도가 바뀌면 사용자가 직접 고친다.
    /// 여기에 숫자를 박아 두고 세법이 바뀌면, 앱이 조용히 틀린 조언을 하게 된다.
    @NSManaged var annualLimitMinor: Int

    /// 이 계좌만의 기대수익률(basis point). 비워 두면 계좌 종류의 기본값을 따른다.
    /// 예금마다 금리가 다르므로 계좌 단위로 적을 수 있어야 한다
    /// (docs/08-feedback.md 11번).
    /// `Int?` 는 `@NSManaged` 가 직접 못 든다. 저장은 `NSNumber?` 로 하고
    /// KVC 이름만 `expectedReturnBP` 로 붙여 준다 — 모델의 칸 이름이 그것이기 때문이다.
    @NSManaged @objc(expectedReturnBP) var expectedReturnBPNumber: NSNumber?

    /// 쓰는 쪽은 예전 그대로 `Int?` 를 본다.
    var expectedReturnBP: Int? {
        get { expectedReturnBPNumber?.intValue }
        set { expectedReturnBPNumber = newValue.map(NSNumber.init(value:)) }
    }

    /// 만기일. ISA 만기처럼 기한이 있는 계좌에 적는다. 1페이지의 유의사항과
    /// 푸터가 읽는다.
    @NSManaged var maturesOn: Date?

    /// 소유자 UUID. 관계(`owner`)와 **함께** 들고 다닌다.
    ///
    /// 공유로 넘어갈 때 레코드를 커스텀 존으로 옮기게 되는데, 그때 관계만
    /// 있으면 옮기다 끊어져도 복구할 근거가 없다. ADR-0004 가 이걸 하라고
    /// 적어 두고도 안 돼 있었다 (docs/08-feedback.md 13번).
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
