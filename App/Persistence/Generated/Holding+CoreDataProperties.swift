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
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
