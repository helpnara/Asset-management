// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension Plan {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Plan> {
        NSFetchRequest<Plan>(entityName: "Plan")
    }

    @NSManaged var id: UUID

    @NSManaged var title: String

    @NSManaged var startYear: Int

    @NSManaged var startedOn: Date?

    @NSManaged var asOfNote: String

    @NSManaged var declaration: String

    @NSManaged var retirementYear: Int

    @NSManaged var monthlyContributionMinor: Int

    @NSManaged var annualReturnBP: Int

    @NSManaged var contributionGrowthBP: Int

    @NSManaged var inflationBP: Int

    @NSManaged var lowYieldReturnBP: Int

    @NSManaged var realEstateReturnBP: Int

    @NSManaged var targetAmountMinor: Int

    @NSManaged var monthlySpendingMinor: Int

    @NSManaged var withdrawalRateBP: Int

    @NSManaged var monthlyIncomeMinor: Int

    @NSManaged var savingsFloorBP: Int

    @NSManaged var illiquidCapBP: Int

    @NSManaged var usTargetBP: Int

    @NSManaged var mixToleranceBP: Int

    @NSManaged var driftToleranceBP: Int

    @NSManaged var driftRelativeBP: Int

    @NSManaged var disabledDiagnosesRaw: String

    @NSManaged var contributionOrderRaw: String

    @NSManaged var usesMemberContributions: Bool

    @NSManaged var horizonYear: Int

    @NSManaged var createdAt: Date

    @NSManaged var updatedAt: Date?
}
