// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

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
}
