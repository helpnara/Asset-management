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


extension ChangeLog {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChangeLog> {
        NSFetchRequest<ChangeLog>(entityName: "ChangeLog")
    }

    @NSManaged var id: UUID

    @NSManaged var at: Date

    /// 누가. 공유 전에는 기기 이름, 공유 후에는 참가자 이름이 들어간다.
    @NSManaged var actor: String

    @NSManaged var kindRaw: String

    /// 무엇을. `아빠 / ISA / TIGER 미국S&P500` 처럼 사람이 읽는 경로다.
    @NSManaged var subject: String

    /// 어떻게. `2,850,199 → 2,910,000`
    @NSManaged var summary: String
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
