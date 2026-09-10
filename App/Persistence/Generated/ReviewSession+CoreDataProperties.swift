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


extension ReviewSession {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ReviewSession> {
        NSFetchRequest<ReviewSession>(entityName: "ReviewSession")
    }

    @NSManaged var id: UUID

    /// 그 주 토요일(00:00)로 정규화한 값. 주차의 키다.
    @NSManaged var weekAnchor: Date

    @NSManaged var startedAt: Date

    @NSManaged var completedAt: Date?

    @NSManaged var enteredCount: Int

    @NSManaged var totalCount: Int

    /// 알림에서 총액만 적고 넘어간 주. 궤적의 점은 남고 분해는 비어 있다.
    @NSManaged var isTotalOnly: Bool

    @NSManaged var totalValueMinor: Int

    @NSManaged var previousTotalValueMinor: Int

    /// **이번 주에 제 몫을 적은 구성원** — 쉼표로 이은 구성원 `id` (C8).
    /// 구성원별 "N주 연속" 은 이 칸을 주마다 거슬러 세는 것이다. `lastEnteredAt`
    /// 은 마지막 한 번만 남아 지난주까지밖에 못 보므로 여기 남긴다.
    /// 배열 칸을 CloudKit 에 더하지 않으려고 `Member.editorIDs` 와 같은 꼴이다.
    @NSManaged var enteredMemberIDs: String
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
