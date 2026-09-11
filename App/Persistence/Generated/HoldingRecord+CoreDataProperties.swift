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
import CoreData
import Foundation


extension HoldingRecord {

    @nonobjc class func fetchRequest() -> NSFetchRequest<HoldingRecord> {
        NSFetchRequest<HoldingRecord>(entityName: "HoldingRecord")
    }

    @NSManaged var id: UUID

    /// 그 주 토요일(00:00). `ReviewSession.weekAnchor` 와 같은 키.
    @NSManaged var weekAnchor: Date

    /// 어느 종목의 값인가. 종목이 지워져도 줄은 남는다.
    @NSManaged var holdingID: UUID

    /// 종목·계좌 이름을 복사해 둔다 — 지워진 종목의 기록도 읽을 수 있게.
    @NSManaged var holdingName: String

    @NSManaged var accountName: String

    @NSManaged var memberID: UUID

    /// 점검을 끝내던 순간의 평가액.
    @NSManaged var valueMinor: Int
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
