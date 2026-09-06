import Foundation
import SwiftData

/// 전체 백업. **이 파일 하나에 앱의 모든 기록이 들어간다.**
///
/// CSV 도 있지만 그건 보기 좋으라고 있는 것이고, 담기는 것은 주간 기록과
/// 보유 종목뿐이었다 — 구성원·계좌·계획 설정·목돈·연금·할 일·마일스톤이
/// 통째로 빠져 있었다 (docs/08-feedback.md 12번).
///
/// 지금 이 기록의 사본은 아이폰 하나뿐이다. CloudKit 스키마를 Production 에
/// 올리기 전까지 **이 파일이 유일한 안전망**이다.
///
/// 가져오기는 만들지 않는다. 사용자가 직접 입력하기로 한 결정 그대로다
/// (ADR-0005). 되살릴 일이 생기면 그때 만든다 — 그때도 이 파일만 있으면 된다.
struct BackupDocument: Codable, Sendable {
    /// 형식이 바뀌면 올린다. 나중에 읽는 쪽이 이 숫자를 보고 갈래를 탄다.
    var formatVersion: Int = 1
    var exportedAt: Date
    var appVersion: String

    var plan: PlanData?
    var members: [MemberData]
    var cashEvents: [CashEventData]
    var incomes: [IncomeStreamData]
    var milestones: [MilestoneData]
    var todos: [TodoData]
    var scenarios: [ScenarioData]
    var reviewSessions: [ReviewSessionData]
    var snapshots: [SnapshotData]

    struct PlanData: Codable, Sendable {
        var id: UUID
        var title: String
        var startYear: Int
        var retirementYear: Int
        var horizonYear: Int
        var monthlyContributionMinor: Int
        var contributionGrowthBP: Int
        var annualReturnBP: Int
        var inflationBP: Int
        var targetAmountMinor: Int
        var monthlySpendingMinor: Int
        var withdrawalRateBP: Int
        var monthlyIncomeMinor: Int
        var savingsFloorBP: Int
        var illiquidCapBP: Int
        var usTargetBP: Int
        var mixToleranceBP: Int
        var usesMemberContributions: Bool
        var createdAt: Date
    }

    struct MemberData: Codable, Sendable {
        var id: UUID
        var name: String
        var roleNote: String
        var birthYear: Int
        var birthMonth: Int
        var taxResidency: String
        var targetRetirementAge: Int
        var monthlyContributionMinor: Int
        var colorIndex: Int
        var sortIndex: Int
        var createdAt: Date
        var accounts: [AccountData]
    }

    struct AccountData: Codable, Sendable {
        var id: UUID
        var name: String
        var institution: String
        var kind: String
        var isArchived: Bool
        var annualContributionMinor: Int
        var annualLimitMinor: Int
        var sortIndex: Int
        var createdAt: Date
        var holdings: [HoldingData]
    }

    struct HoldingData: Codable, Sendable {
        var id: UUID
        var name: String
        var assetClass: String
        var instrumentType: String
        var listingCountryCode: String
        var status: String
        var cadence: String
        var valueMinor: Int
        var lastEnteredValueMinor: Int
        var lastEnteredAt: Date?
        var note: String
        var sortIndex: Int
        var createdAt: Date
    }

    struct CashEventData: Codable, Sendable {
        var id: UUID
        var date: Date
        var label: String
        var amountMinor: Int
        var isAlreadyReflected: Bool
        var note: String
        var sortIndex: Int
    }

    struct IncomeStreamData: Codable, Sendable {
        var id: UUID
        var label: String
        var monthlyAmountMinor: Int
        var startYear: Int
        var endYear: Int
        var isInflationLinked: Bool
        var sortIndex: Int
    }

    struct MilestoneData: Codable, Sendable {
        var id: UUID
        var year: Int
        var label: String
        var note: String
        var sortIndex: Int
    }

    struct TodoData: Codable, Sendable {
        var id: UUID
        var title: String
        var detail: String
        var category: String
        var dueDate: Date?
        var isDone: Bool
        var repeatsYearly: Bool
        var completedAt: Date?
        var sortIndex: Int
        var createdAt: Date
    }

    struct ScenarioData: Codable, Sendable {
        var id: UUID
        var name: String
        var monthlyMinor: Int
        var retirementYear: Int
        var returnBP: Int
        var volatilityBP: Int
        var projectedMinor: Int
        var createdAt: Date
    }

    struct ReviewSessionData: Codable, Sendable {
        var id: UUID
        var weekAnchor: Date
        var startedAt: Date
        var completedAt: Date?
        var enteredCount: Int
        var totalCount: Int
        var isTotalOnly: Bool
        var totalValueMinor: Int
        var previousTotalValueMinor: Int
    }

    struct SnapshotData: Codable, Sendable {
        var id: UUID
        var weekAnchor: Date
        var netWorthMinor: Int
        var investableMinor: Int
        var liabilitiesMinor: Int
        var lines: [SnapshotLineData]
    }

    struct SnapshotLineData: Codable, Sendable {
        var id: UUID
        var memberID: UUID
        var memberName: String
        var valueMinor: Int
        var sortIndex: Int
    }
}

extension BackupDocument {
    /// `@Model` 을 값으로 옮긴다.
    ///
    /// **여기서 전부 값으로 바꾸는 이유**는 SwiftData 의 `@Model` 이 참조 타입이라
    /// `Sendable` 이 아니고, 파일로 만들어 공유하는 과정이 `async` 경계를 넘기
    /// 때문이다. 화면에서 필요한 값만 뽑아 구조체로 건넨다는 규칙 그대로다
    /// (CLAUDE.md).
    @MainActor
    static func make(from context: ModelContext) -> BackupDocument {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let members = all(Member.self)
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .map { member in
                MemberData(
                    id: member.id, name: member.name, roleNote: member.roleNote,
                    birthYear: member.birthYear, birthMonth: member.birthMonth,
                    taxResidency: member.taxResidencyRaw,
                    targetRetirementAge: member.targetRetirementAge,
                    monthlyContributionMinor: member.monthlyContributionMinor,
                    colorIndex: member.colorIndex, sortIndex: member.sortIndex,
                    createdAt: member.createdAt,
                    accounts: member.sortedAccounts.map { account in
                        AccountData(
                            id: account.id, name: account.name,
                            institution: account.institution, kind: account.kindRaw,
                            isArchived: account.isArchived,
                            annualContributionMinor: account.annualContributionMinor,
                            annualLimitMinor: account.annualLimitMinor,
                            sortIndex: account.sortIndex, createdAt: account.createdAt,
                            holdings: account.sortedHoldings.map { holding in
                                HoldingData(
                                    id: holding.id, name: holding.name,
                                    assetClass: holding.assetClassRaw,
                                    instrumentType: holding.instrumentTypeRaw,
                                    listingCountryCode: holding.listingCountryCode,
                                    status: holding.statusRaw, cadence: holding.cadenceRaw,
                                    valueMinor: holding.valueMinor,
                                    lastEnteredValueMinor: holding.lastEnteredValueMinor,
                                    lastEnteredAt: holding.lastEnteredAt,
                                    note: holding.note, sortIndex: holding.sortIndex,
                                    createdAt: holding.createdAt
                                )
                            }
                        )
                    }
                )
            }

        let plan = all(Plan.self).first.map { plan in
            PlanData(
                id: plan.id, title: plan.title, startYear: plan.startYear,
                retirementYear: plan.retirementYear, horizonYear: plan.horizonYear,
                monthlyContributionMinor: plan.monthlyContributionMinor,
                contributionGrowthBP: plan.contributionGrowthBP,
                annualReturnBP: plan.annualReturnBP, inflationBP: plan.inflationBP,
                targetAmountMinor: plan.targetAmountMinor,
                monthlySpendingMinor: plan.monthlySpendingMinor,
                withdrawalRateBP: plan.withdrawalRateBP,
                monthlyIncomeMinor: plan.monthlyIncomeMinor,
                savingsFloorBP: plan.savingsFloorBP,
                illiquidCapBP: plan.illiquidCapBP, usTargetBP: plan.usTargetBP,
                mixToleranceBP: plan.mixToleranceBP,
                usesMemberContributions: plan.usesMemberContributions,
                createdAt: plan.createdAt
            )
        }

        return BackupDocument(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            plan: plan,
            members: members,
            cashEvents: all(CashEvent.self).sorted { $0.date < $1.date }.map {
                CashEventData(id: $0.id, date: $0.date, label: $0.label,
                              amountMinor: $0.amountMinor,
                              isAlreadyReflected: $0.isAlreadyReflected,
                              note: $0.note, sortIndex: $0.sortIndex)
            },
            incomes: all(IncomeStream.self).sorted { $0.sortIndex < $1.sortIndex }.map {
                IncomeStreamData(id: $0.id, label: $0.label,
                                 monthlyAmountMinor: $0.monthlyAmountMinor,
                                 startYear: $0.startYear, endYear: $0.endYear,
                                 isInflationLinked: $0.isInflationLinked,
                                 sortIndex: $0.sortIndex)
            },
            milestones: all(UserMilestone.self).sorted { $0.year < $1.year }.map {
                MilestoneData(id: $0.id, year: $0.year, label: $0.label,
                              note: $0.note, sortIndex: $0.sortIndex)
            },
            todos: all(TodoItem.self).sorted { $0.sortIndex < $1.sortIndex }.map {
                TodoData(id: $0.id, title: $0.title, detail: $0.detail,
                         category: $0.categoryRaw, dueDate: $0.dueDate,
                         isDone: $0.isDone, repeatsYearly: $0.repeatsYearly,
                         completedAt: $0.completedAt, sortIndex: $0.sortIndex,
                         createdAt: $0.createdAt)
            },
            scenarios: all(Scenario.self).sorted { $0.createdAt < $1.createdAt }.map {
                ScenarioData(id: $0.id, name: $0.name, monthlyMinor: $0.monthlyMinor,
                             retirementYear: $0.retirementYear, returnBP: $0.returnBP,
                             volatilityBP: $0.volatilityBP,
                             projectedMinor: $0.projectedMinor, createdAt: $0.createdAt)
            },
            reviewSessions: all(ReviewSession.self).sorted { $0.weekAnchor < $1.weekAnchor }.map {
                ReviewSessionData(id: $0.id, weekAnchor: $0.weekAnchor,
                                  startedAt: $0.startedAt, completedAt: $0.completedAt,
                                  enteredCount: $0.enteredCount, totalCount: $0.totalCount,
                                  isTotalOnly: $0.isTotalOnly,
                                  totalValueMinor: $0.totalValueMinor,
                                  previousTotalValueMinor: $0.previousTotalValueMinor)
            },
            snapshots: all(Snapshot.self).sorted { $0.weekAnchor < $1.weekAnchor }.map { snapshot in
                SnapshotData(id: snapshot.id, weekAnchor: snapshot.weekAnchor,
                             netWorthMinor: snapshot.netWorthMinor,
                             investableMinor: snapshot.investableMinor,
                             liabilitiesMinor: snapshot.liabilitiesMinor,
                             lines: snapshot.sortedLines.map {
                                 SnapshotLineData(id: $0.id, memberID: $0.memberID,
                                                  memberName: $0.memberName,
                                                  valueMinor: $0.valueMinor,
                                                  sortIndex: $0.sortIndex)
                             })
            }
        )
    }

    /// 사람이 열어 봐도 읽히도록 들여쓰고 키를 정렬한다. 백업은 언젠가
    /// 눈으로 확인하게 된다.
    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)) ?? Data()
    }

    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "느린부자의기록 백업 \(formatter.string(from: exportedAt)).json"
    }
}
