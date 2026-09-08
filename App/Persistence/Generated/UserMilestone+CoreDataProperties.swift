// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension UserMilestone {

    @nonobjc class func fetchRequest() -> NSFetchRequest<UserMilestone> {
        NSFetchRequest<UserMilestone>(entityName: "UserMilestone")
    }

    @NSManaged var id: UUID

    @NSManaged var year: Int

    @NSManaged var label: String

    @NSManaged var note: String

    @NSManaged var sortIndex: Int

    /// 누구의 일인가. `nil` 이면 **가족 전체**의 일이다
    /// (docs/08-feedback.md 32번).
    ///
    /// 관계가 아니라 UUID 로 든다 — 마일스톤은 그 사람이 지워져도 남아야
    /// 하는 기록이고(전학·이사처럼 사람이 빠져도 그 해는 있었다), 관계로
    /// 묶으면 cascade 에 딸려 사라진다.
    ///
    /// CloudKit 제약대로 옵셔널이고 기본값이 있다 (ADR-0001).
    @NSManaged var memberID: UUID?
}
