// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension IncomeStream {

    @nonobjc class func fetchRequest() -> NSFetchRequest<IncomeStream> {
        NSFetchRequest<IncomeStream>(entityName: "IncomeStream")
    }

    @NSManaged var id: UUID

    @NSManaged var label: String

    /// 오늘 돈 기준 월 수령액.
    @NSManaged var monthlyAmountMinor: Int

    @NSManaged var startYear: Int

    /// 0이면 종신.
    @NSManaged var endYear: Int

    /// 물가에 연동되는가. 국민연금은 연동되고 확정형 개인연금은 안 된다.
    /// 30년이면 이 차이가 결과를 절반으로 가른다.
    @NSManaged var isInflationLinked: Bool

    @NSManaged var sortIndex: Int
}
