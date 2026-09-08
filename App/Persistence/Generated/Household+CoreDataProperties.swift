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


extension Household {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Household> {
        NSFetchRequest<Household>(entityName: "Household")
    }

    @NSManaged var id: UUID

    /// 지금은 아무 화면도 안 읽는다. `CKShare` 에 붙일 이름이 필요할 때 쓴다 —
    /// 화면 제목은 `Plan.title` 이지 이것이 아니다.
    @NSManaged var title: String

    @NSManaged var createdAt: Date

    @NSManaged var accounts: NSSet?

    @NSManaged var cashEvents: NSSet?

    @NSManaged var changeLogs: NSSet?

    @NSManaged var familyTargets: NSSet?

    @NSManaged var holdings: NSSet?

    @NSManaged var incomeStreams: NSSet?

    @NSManaged var members: NSSet?

    @NSManaged var plans: NSSet?

    @NSManaged var principles: NSSet?

    @NSManaged var reviewSessions: NSSet?

    @NSManaged var scenarios: NSSet?

    @NSManaged var snapshots: NSSet?

    @NSManaged var snapshotLines: NSSet?

    @NSManaged var todoItems: NSSet?

    @NSManaged var userMilestones: NSSet?

}

extension Household {

    @objc(addAccountsObject:)
    @NSManaged func addToAccounts(_ value: Account)

    @objc(removeAccountsObject:)
    @NSManaged func removeFromAccounts(_ value: Account)

    @objc(addAccounts:)
    @NSManaged func addToAccounts(_ values: NSSet)

    @objc(removeAccounts:)
    @NSManaged func removeFromAccounts(_ values: NSSet)

    @objc(addCashEventsObject:)
    @NSManaged func addToCashEvents(_ value: CashEvent)

    @objc(removeCashEventsObject:)
    @NSManaged func removeFromCashEvents(_ value: CashEvent)

    @objc(addCashEvents:)
    @NSManaged func addToCashEvents(_ values: NSSet)

    @objc(removeCashEvents:)
    @NSManaged func removeFromCashEvents(_ values: NSSet)

    @objc(addChangeLogsObject:)
    @NSManaged func addToChangeLogs(_ value: ChangeLog)

    @objc(removeChangeLogsObject:)
    @NSManaged func removeFromChangeLogs(_ value: ChangeLog)

    @objc(addChangeLogs:)
    @NSManaged func addToChangeLogs(_ values: NSSet)

    @objc(removeChangeLogs:)
    @NSManaged func removeFromChangeLogs(_ values: NSSet)

    @objc(addFamilyTargetsObject:)
    @NSManaged func addToFamilyTargets(_ value: FamilyTarget)

    @objc(removeFamilyTargetsObject:)
    @NSManaged func removeFromFamilyTargets(_ value: FamilyTarget)

    @objc(addFamilyTargets:)
    @NSManaged func addToFamilyTargets(_ values: NSSet)

    @objc(removeFamilyTargets:)
    @NSManaged func removeFromFamilyTargets(_ values: NSSet)

    @objc(addHoldingsObject:)
    @NSManaged func addToHoldings(_ value: Holding)

    @objc(removeHoldingsObject:)
    @NSManaged func removeFromHoldings(_ value: Holding)

    @objc(addHoldings:)
    @NSManaged func addToHoldings(_ values: NSSet)

    @objc(removeHoldings:)
    @NSManaged func removeFromHoldings(_ values: NSSet)

    @objc(addIncomeStreamsObject:)
    @NSManaged func addToIncomeStreams(_ value: IncomeStream)

    @objc(removeIncomeStreamsObject:)
    @NSManaged func removeFromIncomeStreams(_ value: IncomeStream)

    @objc(addIncomeStreams:)
    @NSManaged func addToIncomeStreams(_ values: NSSet)

    @objc(removeIncomeStreams:)
    @NSManaged func removeFromIncomeStreams(_ values: NSSet)

    @objc(addMembersObject:)
    @NSManaged func addToMembers(_ value: Member)

    @objc(removeMembersObject:)
    @NSManaged func removeFromMembers(_ value: Member)

    @objc(addMembers:)
    @NSManaged func addToMembers(_ values: NSSet)

    @objc(removeMembers:)
    @NSManaged func removeFromMembers(_ values: NSSet)

    @objc(addPlansObject:)
    @NSManaged func addToPlans(_ value: Plan)

    @objc(removePlansObject:)
    @NSManaged func removeFromPlans(_ value: Plan)

    @objc(addPlans:)
    @NSManaged func addToPlans(_ values: NSSet)

    @objc(removePlans:)
    @NSManaged func removeFromPlans(_ values: NSSet)

    @objc(addPrinciplesObject:)
    @NSManaged func addToPrinciples(_ value: Principle)

    @objc(removePrinciplesObject:)
    @NSManaged func removeFromPrinciples(_ value: Principle)

    @objc(addPrinciples:)
    @NSManaged func addToPrinciples(_ values: NSSet)

    @objc(removePrinciples:)
    @NSManaged func removeFromPrinciples(_ values: NSSet)

    @objc(addReviewSessionsObject:)
    @NSManaged func addToReviewSessions(_ value: ReviewSession)

    @objc(removeReviewSessionsObject:)
    @NSManaged func removeFromReviewSessions(_ value: ReviewSession)

    @objc(addReviewSessions:)
    @NSManaged func addToReviewSessions(_ values: NSSet)

    @objc(removeReviewSessions:)
    @NSManaged func removeFromReviewSessions(_ values: NSSet)

    @objc(addScenariosObject:)
    @NSManaged func addToScenarios(_ value: Scenario)

    @objc(removeScenariosObject:)
    @NSManaged func removeFromScenarios(_ value: Scenario)

    @objc(addScenarios:)
    @NSManaged func addToScenarios(_ values: NSSet)

    @objc(removeScenarios:)
    @NSManaged func removeFromScenarios(_ values: NSSet)

    @objc(addSnapshotsObject:)
    @NSManaged func addToSnapshots(_ value: Snapshot)

    @objc(removeSnapshotsObject:)
    @NSManaged func removeFromSnapshots(_ value: Snapshot)

    @objc(addSnapshots:)
    @NSManaged func addToSnapshots(_ values: NSSet)

    @objc(removeSnapshots:)
    @NSManaged func removeFromSnapshots(_ values: NSSet)

    @objc(addSnapshotLinesObject:)
    @NSManaged func addToSnapshotLines(_ value: SnapshotLine)

    @objc(removeSnapshotLinesObject:)
    @NSManaged func removeFromSnapshotLines(_ value: SnapshotLine)

    @objc(addSnapshotLines:)
    @NSManaged func addToSnapshotLines(_ values: NSSet)

    @objc(removeSnapshotLines:)
    @NSManaged func removeFromSnapshotLines(_ values: NSSet)

    @objc(addTodoItemsObject:)
    @NSManaged func addToTodoItems(_ value: TodoItem)

    @objc(removeTodoItemsObject:)
    @NSManaged func removeFromTodoItems(_ value: TodoItem)

    @objc(addTodoItems:)
    @NSManaged func addToTodoItems(_ values: NSSet)

    @objc(removeTodoItems:)
    @NSManaged func removeFromTodoItems(_ values: NSSet)

    @objc(addUserMilestonesObject:)
    @NSManaged func addToUserMilestones(_ value: UserMilestone)

    @objc(removeUserMilestonesObject:)
    @NSManaged func removeFromUserMilestones(_ value: UserMilestone)

    @objc(addUserMilestones:)
    @NSManaged func addToUserMilestones(_ values: NSSet)

    @objc(removeUserMilestones:)
    @NSManaged func removeFromUserMilestones(_ values: NSSet)
}
