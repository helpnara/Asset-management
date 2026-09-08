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

    /// 사용자가 매주 직접 적어 넣는 평가액. 이 앱의 진실의 원천이다 (ADR-0005).
    @NSManaged var valueMinor: Int

    /// 직전 점검에서 적은 값. 증감 표시에만 쓴다.
    @NSManaged var lastEnteredValueMinor: Int

    @NSManaged var lastEnteredAt: Date?

    @NSManaged var note: String

    /// **이 종목이 속한 계좌 안에서**의 목표 비중 (basis point).
    ///
    /// 분모가 계좌인 이유는 계좌마다 투자 목적과 규모가 다르기 때문이다.
    /// 한 계좌 안 종목들의 목표는 **합이 100%** 가 되어야 한다
    /// (docs/08-feedback.md 15번).
    ///
    /// nil 이면 아직 안 정한 것이고, 그건 조용히 넘어갈 일이 아니라 알림거리다.
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

    /// 계좌 UUID. `Account.ownerID` 와 같은 이유로 관계와 함께 들고 다닌다.
    @NSManaged var accountID: UUID?

    @NSManaged var account: Account?
}
