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


extension CashEvent {

    @nonobjc class func fetchRequest() -> NSFetchRequest<CashEvent> {
        NSFetchRequest<CashEvent>(entityName: "CashEvent")
    }

    @NSManaged var id: UUID

    @NSManaged var date: Date

    @NSManaged var label: String

    /// 부호로 방향을 표현한다. 양수는 유입, 음수는 유출.
    @NSManaged var amountMinor: Int

    /// 이미 현재 잔고에 반영된 이벤트. 예측에서 빼야 두 번 세지 않는다.
    ///
    /// 1페이지의 "이 표의 모든 금액은 이사 완료 후 기준 — 중복 계산 방지" 가
    /// 바로 이 문제였다.
    @NSManaged var isAlreadyReflected: Bool

    @NSManaged var note: String

    @NSManaged var sortIndex: Int
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
