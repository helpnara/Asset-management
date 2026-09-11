import Core
import Foundation
import CoreData

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
    var principles: [PrincipleData]
    /// 변경 이력은 **백업에는 넣고 1페이지에는 안 넣는다.** 이력에 금액이
    /// 남으므로 남에게 건네는 문서에 들어가면 안 된다 (docs/08-feedback.md 13번).
    var changeLog: [ChangeLogData]
    /// 가족 전체의 지역·자산군 목표 (docs/08-feedback.md 15번).
    var familyTargets: [FamilyTargetData]
    /// 목실감 일기. 이 기기 사용자의 개인 기록이라 백업에는 넣고 공유에는 안
    /// 넣는다. 옛 백업에는 없으므로 옵셔널이다.
    var diary: [DiaryData]?
    /// 종목별 주간 값 (A3, 빌드 67 부터). 옛 백업에는 없다.
    var holdingRecords: [HoldingRecordData]?

    struct HoldingRecordData: Codable, Sendable {
        var id: UUID
        var weekAnchor: Date
        var holdingID: UUID
        var holdingName: String
        var accountName: String
        var memberID: UUID
        var valueMinor: Int
    }

    struct DiaryData: Codable, Sendable {
        var id: UUID
        var day: Date
        var goal: String
        var result: String
        var gratitude: String
        var createdAt: Date
    }

    struct FamilyTargetData: Codable, Sendable {
        var id: UUID
        var dimension: String
        var key: String
        var targetBP: Int
    }

    struct PlanData: Codable, Sendable {
        var id: UUID
        var title: String
        var startedOn: Date?
        var asOfNote: String
        var declaration: String
        var startYear: Int
        var retirementYear: Int
        var horizonYear: Int
        var monthlyContributionMinor: Int
        var contributionGrowthBP: Int
        var annualReturnBP: Int
        var inflationBP: Int
        /// 옛 백업에는 없다 — 되돌릴 때 기본 5% (67번).
        var postRetirementReturnBP: Int?
        var lowYieldReturnBP: Int
        var realEstateReturnBP: Int
        var targetAmountMinor: Int
        var monthlySpendingMinor: Int
        var withdrawalRateBP: Int
        var monthlyIncomeMinor: Int
        var savingsFloorBP: Int
        var illiquidCapBP: Int
        var usTargetBP: Int
        var mixToleranceBP: Int
        var usesMemberContributions: Bool
        var driftToleranceBP: Int
        var driftRelativeBP: Int
        var createdAt: Date
        var updatedAt: Date?
        /// 진단 규칙 켜짐·채우는 순서 (docs/08-feedback.md 47번).
        /// 옛 백업에는 없으므로 옵셔널이라야 읽힌다.
        var disabledDiagnosesRaw: String?
        var contributionOrderRaw: String?
        /// 자산군별 기대수익률 (D6, 빌드 66 부터). 옛 백업에는 없다.
        var bondReturnBP: Int?
        var commodityReturnBP: Int?
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
        var employerMatchMinor: Int
        /// 옛 백업에는 없다 — 옵셔널로 두고 되돌릴 때 0 으로 본다.
        var monthlySalaryMinor: Int?
        var otherIncomeMinor: Int?
        var note: String
        /// 참가자별 편집 권한 (58번). 옛 백업에는 없다.
        var editorIDs: String?
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
        var expectedReturnBP: Int?
        var maturesOn: Date?
        var ownerID: UUID?
        /// 옛 백업에는 없다 — 옵셔널로 두고 되돌릴 때 0 으로 본다.
        var purchasePriceMinor: Int?
        var monthlyRentMinor: Int?
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
        var targetWeightBP: Int?
        var accountID: UUID?
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
        /// 누구의 일인가. 없으면 가족 전체 (docs/08-feedback.md 32번).
        /// 옛 백업 파일에는 이 칸이 없으므로 옵셔널이라야 읽힌다.
        var memberID: UUID?
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
        /// 빌드 61 부터 (C8). 옛 백업에는 없어 옵셔널이다.
        var enteredMemberIDs: String?
        /// 빌드 66 부터 (A9). 그 주의 진단 결과.
        var diagnosisRaw: String?
    }

    struct SnapshotData: Codable, Sendable {
        var id: UUID
        var weekAnchor: Date
        var netWorthMinor: Int
        var investableMinor: Int
        var liabilitiesMinor: Int
        var lines: [SnapshotLineData]
    }

    struct PrincipleData: Codable, Sendable {
        var id: UUID
        var order: Int
        var title: String
        var detail: String
        var reviewNote: String
        var createdAt: Date
    }

    struct ChangeLogData: Codable, Sendable {
        var id: UUID
        var at: Date
        var actor: String
        var kind: String
        var subject: String
        var summary: String
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
    static func make(from context: NSManagedObjectContext) -> BackupDocument {

        let members = context.all(Member.self)
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .map { member in
                MemberData(
                    id: member.id, name: member.name, roleNote: member.roleNote,
                    birthYear: member.birthYear, birthMonth: member.birthMonth,
                    taxResidency: member.taxResidencyRaw,
                    targetRetirementAge: member.targetRetirementAge,
                    monthlyContributionMinor: member.monthlyContributionMinor,
                    employerMatchMinor: member.employerMatchMinor,
                    monthlySalaryMinor: member.monthlySalaryMinor,
                    otherIncomeMinor: member.otherIncomeMinor,
                    note: member.note,
                    editorIDs: member.editorIDs,
                    colorIndex: member.colorIndex, sortIndex: member.sortIndex,
                    createdAt: member.createdAt,
                    accounts: member.sortedAccounts.map { account in
                        AccountData(
                            id: account.id, name: account.name,
                            institution: account.institution, kind: account.kindRaw,
                            isArchived: account.isArchived,
                            annualContributionMinor: account.annualContributionMinor,
                            annualLimitMinor: account.annualLimitMinor,
                            expectedReturnBP: account.expectedReturnBP,
                            maturesOn: account.maturesOn,
                            ownerID: account.ownerID ?? member.id,
                            purchasePriceMinor: account.purchasePriceMinor,
                            monthlyRentMinor: account.monthlyRentMinor,
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
                                    note: holding.note,
                                    targetWeightBP: holding.targetWeightBP,
                                    accountID: holding.accountID ?? account.id,
                                    sortIndex: holding.sortIndex,
                                    createdAt: holding.createdAt
                                )
                            }
                        )
                    }
                )
            }

        let plan = context.all(Plan.self).first.map { plan in
            PlanData(
                id: plan.id, title: plan.title,
                startedOn: plan.startedOn, asOfNote: plan.asOfNote,
                declaration: plan.declaration, startYear: plan.startYear,
                retirementYear: plan.retirementYear, horizonYear: plan.horizonYear,
                monthlyContributionMinor: plan.monthlyContributionMinor,
                contributionGrowthBP: plan.contributionGrowthBP,
                annualReturnBP: plan.annualReturnBP, inflationBP: plan.inflationBP,
                postRetirementReturnBP: plan.postRetirementReturnBP,
                lowYieldReturnBP: plan.lowYieldReturnBP,
                realEstateReturnBP: plan.realEstateReturnBP,
                targetAmountMinor: plan.targetAmountMinor,
                monthlySpendingMinor: plan.monthlySpendingMinor,
                withdrawalRateBP: plan.withdrawalRateBP,
                monthlyIncomeMinor: plan.monthlyIncomeMinor,
                savingsFloorBP: plan.savingsFloorBP,
                illiquidCapBP: plan.illiquidCapBP, usTargetBP: plan.usTargetBP,
                mixToleranceBP: plan.mixToleranceBP,
                usesMemberContributions: plan.usesMemberContributions,
                driftToleranceBP: plan.driftToleranceBP,
                driftRelativeBP: plan.driftRelativeBP,
                createdAt: plan.createdAt,
                updatedAt: plan.updatedAt,
                // 선언 순서와 같아야 한다 — 멤버와이즈 초기화는 순서를 지킨다.
                disabledDiagnosesRaw: plan.disabledDiagnosesRaw,
                contributionOrderRaw: plan.contributionOrderRaw,
                bondReturnBP: plan.bondReturnBP,
                commodityReturnBP: plan.commodityReturnBP
            )
        }

        return BackupDocument(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            plan: plan,
            members: members,
            cashEvents: context.all(CashEvent.self).sorted { $0.date < $1.date }.map {
                CashEventData(id: $0.id, date: $0.date, label: $0.label,
                              amountMinor: $0.amountMinor,
                              isAlreadyReflected: $0.isAlreadyReflected,
                              note: $0.note, sortIndex: $0.sortIndex)
            },
            incomes: context.all(IncomeStream.self).sorted { $0.sortIndex < $1.sortIndex }.map {
                IncomeStreamData(id: $0.id, label: $0.label,
                                 monthlyAmountMinor: $0.monthlyAmountMinor,
                                 startYear: $0.startYear, endYear: $0.endYear,
                                 isInflationLinked: $0.isInflationLinked,
                                 sortIndex: $0.sortIndex)
            },
            milestones: context.all(UserMilestone.self).sorted { $0.year < $1.year }.map {
                MilestoneData(id: $0.id, year: $0.year, label: $0.label,
                              note: $0.note, sortIndex: $0.sortIndex,
                              memberID: $0.memberID)
            },
            todos: context.all(TodoItem.self).sorted { $0.sortIndex < $1.sortIndex }.map {
                TodoData(id: $0.id, title: $0.title, detail: $0.detail,
                         category: $0.categoryRaw, dueDate: $0.dueDate,
                         isDone: $0.isDone, repeatsYearly: $0.repeatsYearly,
                         completedAt: $0.completedAt, sortIndex: $0.sortIndex,
                         createdAt: $0.createdAt)
            },
            scenarios: context.all(Scenario.self).sorted { $0.createdAt < $1.createdAt }.map {
                ScenarioData(id: $0.id, name: $0.name, monthlyMinor: $0.monthlyMinor,
                             retirementYear: $0.retirementYear, returnBP: $0.returnBP,
                             volatilityBP: $0.volatilityBP,
                             projectedMinor: $0.projectedMinor, createdAt: $0.createdAt)
            },
            reviewSessions: context.all(ReviewSession.self).sorted { $0.weekAnchor < $1.weekAnchor }.map {
                ReviewSessionData(id: $0.id, weekAnchor: $0.weekAnchor,
                                  startedAt: $0.startedAt, completedAt: $0.completedAt,
                                  enteredCount: $0.enteredCount, totalCount: $0.totalCount,
                                  isTotalOnly: $0.isTotalOnly,
                                  totalValueMinor: $0.totalValueMinor,
                                  previousTotalValueMinor: $0.previousTotalValueMinor,
                                  enteredMemberIDs: $0.enteredMemberIDs,
                                  diagnosisRaw: $0.diagnosisRaw)
            },
            snapshots: context.all(Snapshot.self).sorted { $0.weekAnchor < $1.weekAnchor }.map { snapshot in
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
            },
            principles: context.all(Principle.self).sorted { $0.order < $1.order }.map {
                PrincipleData(id: $0.id, order: $0.order, title: $0.title,
                              detail: $0.detail, reviewNote: $0.reviewNote,
                              createdAt: $0.createdAt)
            },
            changeLog: context.all(ChangeLog.self).sorted { $0.at < $1.at }.map {
                ChangeLogData(id: $0.id, at: $0.at, actor: $0.actor,
                              kind: $0.kindRaw, subject: $0.subject, summary: $0.summary)
            },
            familyTargets: context.all(FamilyTarget.self)
                .sorted { ($0.dimensionRaw, $0.key) < ($1.dimensionRaw, $1.key) }
                .map {
                    FamilyTargetData(id: $0.id, dimension: $0.dimensionRaw,
                                     key: $0.key, targetBP: $0.targetBP)
                },
            diary: context.all(DiaryEntry.self).sorted { $0.day < $1.day }.map {
                DiaryData(id: $0.id, day: $0.day, goal: $0.goal, result: $0.result,
                          gratitude: $0.gratitude, createdAt: $0.createdAt)
            },
            holdingRecords: context.all(HoldingRecord.self)
                .sorted { ($0.weekAnchor, $0.holdingName) < ($1.weekAnchor, $1.holdingName) }
                .map {
                    HoldingRecordData(id: $0.id, weekAnchor: $0.weekAnchor, holdingID: $0.holdingID,
                                      holdingName: $0.holdingName, accountName: $0.accountName,
                                      memberID: $0.memberID, valueMinor: $0.valueMinor)
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

// MARK: - 되돌리기

extension BackupDocument {

    /// 파일에서 읽는다. 형식이 다르면 `nil`.
    static func decode(_ data: Data) -> BackupDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupDocument.self, from: data)
    }

    /// **이 기기의 기록을 백업 파일로 갈아 끼운다** (docs/08-feedback.md 40번).
    ///
    /// 내보내기만 있고 되돌리기가 없었다. 그런데 구성원 하나를 잘못 지우면
    /// 계좌·종목·적어 온 평가액이 cascade 로 함께 사라지고, **iCloud 는 그
    /// 삭제까지 동기화한다** — 거울이지 백업이 아니다. 변경 이력(29번)은
    /// 무엇이 사라졌는지 적기만 하고 되돌리지 못한다.
    ///
    /// **합치지 않고 통째로 바꾼다.** 합치면 같은 것이 두 벌이 되거나 어느 쪽이
    /// 최신인지 판단해야 하는데, 그 판단을 앱이 대신하면 조용히 틀린 값이 남는다.
    /// 지우고 넣는 것은 무슨 일이 일어났는지 사람이 정확히 안다.
    ///
    /// UUID 를 그대로 살려 넣으므로 되돌린 뒤에도 스냅샷의 구성원별 줄이
    /// 같은 사람을 가리킨다.
    @MainActor
    static func restore(_ document: BackupDocument, into context: NSManagedObjectContext) {
        // 1) 비운다. 관계로 딸려 가는 것까지 확실히 하려고 전부 명시한다.
        deleteAll(Member.self, in: context)
        deleteAll(Account.self, in: context)
        deleteAll(Holding.self, in: context)
        deleteAll(Snapshot.self, in: context)
        deleteAll(SnapshotLine.self, in: context)
        deleteAll(ReviewSession.self, in: context)
        deleteAll(Plan.self, in: context)
        deleteAll(CashEvent.self, in: context)
        deleteAll(IncomeStream.self, in: context)
        deleteAll(UserMilestone.self, in: context)
        deleteAll(TodoItem.self, in: context)
        deleteAll(Scenario.self, in: context)
        deleteAll(Principle.self, in: context)
        deleteAll(ChangeLog.self, in: context)
        deleteAll(FamilyTarget.self, in: context)
        deleteAll(HoldingRecord.self, in: context)
        // 일기는 백업에 있을 때만 갈아 끼운다. 옛 백업(일기 칸이 없던 때)으로
        // 되돌린다고 오늘까지 쓴 일기가 지워지면 안 된다.
        if document.diary != nil { deleteAll(DiaryEntry.self, in: context) }

        // 2) 채운다.
        if let data = document.plan { insert(plan: data, into: context) }

        for memberData in document.members {
            let member = Member(context: context, name: memberData.name, roleNote: memberData.roleNote,
                                birthYear: memberData.birthYear,
                                birthMonth: memberData.birthMonth,
                                taxResidency: TaxResidency(rawValue: memberData.taxResidency) ?? .korea,
                                targetRetirementAge: memberData.targetRetirementAge,
                                colorIndex: memberData.colorIndex,
                                sortIndex: memberData.sortIndex)
            member.id = memberData.id
            member.monthlyContributionMinor = memberData.monthlyContributionMinor
            member.employerMatchMinor = memberData.employerMatchMinor
            member.monthlySalaryMinor = memberData.monthlySalaryMinor ?? 0
            member.otherIncomeMinor = memberData.otherIncomeMinor ?? 0
            member.note = memberData.note
            member.editorIDs = memberData.editorIDs ?? ""
            member.createdAt = memberData.createdAt

            for accountData in memberData.accounts {
                let account = Account(context: context, name: accountData.name,
                                      institution: accountData.institution,
                                      kind: AccountKind(rawValue: accountData.kind) ?? .general,
                                      owner: member, sortIndex: accountData.sortIndex)
                account.id = accountData.id
                account.isArchived = accountData.isArchived
                account.annualContributionMinor = accountData.annualContributionMinor
                account.annualLimitMinor = accountData.annualLimitMinor
                account.expectedReturnBP = accountData.expectedReturnBP
                account.maturesOn = accountData.maturesOn
                account.purchasePriceMinor = accountData.purchasePriceMinor ?? 0
                account.monthlyRentMinor = accountData.monthlyRentMinor ?? 0
                account.createdAt = accountData.createdAt

                for holdingData in accountData.holdings {
                    let holding = Holding(context: context,
                        name: holdingData.name,
                        assetClass: AssetClass(rawValue: holdingData.assetClass) ?? .equity,
                        instrumentType: InstrumentType(rawValue: holdingData.instrumentType) ?? .etf,
                        listingCountryCode: holdingData.listingCountryCode,
                        status: HoldingStatus(rawValue: holdingData.status) ?? .accumulating,
                        cadence: EntryCadence(rawValue: holdingData.cadence) ?? .weekly,
                        valueMinor: holdingData.valueMinor,
                        account: account,
                        sortIndex: holdingData.sortIndex
                    )
                    holding.id = holdingData.id
                    holding.lastEnteredValueMinor = holdingData.lastEnteredValueMinor
                    holding.lastEnteredAt = holdingData.lastEnteredAt
                    holding.note = holdingData.note
                    holding.targetWeightBP = holdingData.targetWeightBP
                    holding.createdAt = holdingData.createdAt
                }
            }
        }

        for data in document.cashEvents {
            let event = CashEvent(context: context, date: data.date, label: data.label,
                                  amountMinor: data.amountMinor, sortIndex: data.sortIndex)
            event.id = data.id
            event.isAlreadyReflected = data.isAlreadyReflected
            event.note = data.note
        }

        for data in document.incomes {
            let income = IncomeStream(context: context, label: data.label,
                                      monthlyAmountMinor: data.monthlyAmountMinor,
                                      startYear: data.startYear, sortIndex: data.sortIndex)
            income.id = data.id
            income.endYear = data.endYear
            income.isInflationLinked = data.isInflationLinked
        }

        for data in document.milestones {
            let milestone = UserMilestone(context: context, year: data.year, label: data.label,
                                          sortIndex: data.sortIndex, memberID: data.memberID)
            milestone.id = data.id
            milestone.note = data.note
        }

        for data in document.todos {
            let todo = TodoItem(context: context, title: data.title,
                                category: TodoCategory(rawValue: data.category) ?? .note,
                                sortIndex: data.sortIndex)
            todo.id = data.id
            todo.detail = data.detail
            todo.dueDate = data.dueDate
            todo.isDone = data.isDone
            todo.repeatsYearly = data.repeatsYearly
            todo.completedAt = data.completedAt
            todo.createdAt = data.createdAt
        }

        for data in document.scenarios {
            let scenario = Scenario(context: context, name: data.name, monthlyMinor: data.monthlyMinor,
                                    retirementYear: data.retirementYear,
                                    returnBP: data.returnBP, volatilityBP: data.volatilityBP,
                                    projectedMinor: data.projectedMinor)
            scenario.id = data.id
            scenario.createdAt = data.createdAt
        }

        for data in document.reviewSessions {
            let session = ReviewSession(context: context, weekAnchor: data.weekAnchor, totalCount: data.totalCount)
            session.id = data.id
            session.startedAt = data.startedAt
            session.completedAt = data.completedAt
            session.enteredCount = data.enteredCount
            session.isTotalOnly = data.isTotalOnly
            session.totalValueMinor = data.totalValueMinor
            session.previousTotalValueMinor = data.previousTotalValueMinor
            session.enteredMemberIDs = data.enteredMemberIDs ?? ""
            session.diagnosisRaw = data.diagnosisRaw ?? ""
        }

        for data in document.snapshots {
            let snapshot = Snapshot(context: context, weekAnchor: data.weekAnchor,
                                    netWorthMinor: data.netWorthMinor,
                                    investableMinor: data.investableMinor,
                                    liabilitiesMinor: data.liabilitiesMinor)
            snapshot.id = data.id
            for lineData in data.lines {
                let line = SnapshotLine(context: context, memberID: lineData.memberID,
                                        memberName: lineData.memberName,
                                        valueMinor: lineData.valueMinor,
                                        sortIndex: lineData.sortIndex)
                line.id = lineData.id
                line.snapshot = snapshot
            }
        }

        for data in document.principles {
            let principle = Principle(context: context, order: data.order, title: data.title, detail: data.detail)
            principle.id = data.id
            principle.reviewNote = data.reviewNote
            principle.createdAt = data.createdAt
        }

        for data in document.holdingRecords ?? [] {
            let record = HoldingRecord(context: context)
            record.id = data.id
            record.weekAnchor = data.weekAnchor
            record.holdingID = data.holdingID
            record.holdingName = data.holdingName
            record.accountName = data.accountName
            record.memberID = data.memberID
            record.valueMinor = data.valueMinor
        }

        for data in document.changeLog {
            let log = ChangeLog(context: context, kind: ChangeKind(rawValue: data.kind) ?? .other,
                                subject: data.subject, summary: data.summary, actor: data.actor)
            log.id = data.id
            log.at = data.at
        }

        for data in document.familyTargets {
            let target = FamilyTarget(context: context, dimension: FamilyTarget.Dimension(rawValue: data.dimension) ?? .region,
                                      key: data.key, targetBP: data.targetBP)
            target.id = data.id
        }

        for data in document.diary ?? [] {
            let entry = DiaryEntry(context: context)
            entry.id = data.id
            entry.day = data.day
            entry.goal = data.goal
            entry.result = data.result
            entry.gratitude = data.gratitude
            entry.createdAt = data.createdAt
        }

        // Autosave 를 거치지 않는 저장이라 매달기·저장소 배정을 직접 부른다 (④).
        Household.attachNew(in: context)
        try? context.save()

        // 되돌린 것 자체를 이력에 남긴다. 다음에 "왜 이 값이지?" 를 볼 때
        // 이 한 줄이 답이 된다.
        ChangeLogger.record(.other, subject: "백업 되돌리기",
                            summary: "\(document.suggestedFileName) 으로 되돌렸습니다",
                            in: context)
        Household.attachNew(in: context)
        try? context.save()
    }

    @MainActor
    private static func deleteAll<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) {
        for item in context.all(type) { context.delete(item) }
    }

    /// **데이터 전부 지우기** (docs/05-roadmap.md G3 · docs/02 2.6.4 "데이터 초기화").
    ///
    /// 남이 쓰다 그만두거나 처음부터 다시 시작할 때다. 되돌리기와 같은 길로
    /// 지우되 채우지 않는다 — 그래서 iCloud 로도 삭제가 퍼진다. `Household`
    /// 는 남긴다: 가족 공유의 뿌리라 지우면 초대가 끊기는데, 그건 "가족" 에서
    /// 따로 하는 일이다. 일기도 지운다 — 전부라고 했으면 전부다.
    /// 지운 뒤에는 빈 계획 하나가 새로 선다.
    @MainActor
    static func wipeAll(in context: NSManagedObjectContext) {
        deleteAll(Member.self, in: context)
        deleteAll(Account.self, in: context)
        deleteAll(Holding.self, in: context)
        deleteAll(Snapshot.self, in: context)
        deleteAll(SnapshotLine.self, in: context)
        deleteAll(ReviewSession.self, in: context)
        deleteAll(Plan.self, in: context)
        deleteAll(CashEvent.self, in: context)
        deleteAll(IncomeStream.self, in: context)
        deleteAll(UserMilestone.self, in: context)
        deleteAll(TodoItem.self, in: context)
        deleteAll(Scenario.self, in: context)
        deleteAll(Principle.self, in: context)
        deleteAll(ChangeLog.self, in: context)
        deleteAll(FamilyTarget.self, in: context)
        deleteAll(HoldingRecord.self, in: context)
        deleteAll(DiaryEntry.self, in: context)
        _ = Plan.current(in: context)
        try? context.save()
    }

    @MainActor
    private static func insert(plan data: PlanData, into context: NSManagedObjectContext) {
        let plan = Plan(context: context)
        plan.id = data.id
        plan.title = data.title
        plan.startedOn = data.startedOn
        plan.asOfNote = data.asOfNote
        plan.declaration = data.declaration
        plan.startYear = data.startYear
        plan.retirementYear = data.retirementYear
        plan.horizonYear = data.horizonYear
        plan.monthlyContributionMinor = data.monthlyContributionMinor
        plan.contributionGrowthBP = data.contributionGrowthBP
        plan.annualReturnBP = data.annualReturnBP
        plan.inflationBP = data.inflationBP
        plan.postRetirementReturnBP = data.postRetirementReturnBP ?? 500
        plan.lowYieldReturnBP = data.lowYieldReturnBP
        plan.realEstateReturnBP = data.realEstateReturnBP
        plan.targetAmountMinor = data.targetAmountMinor
        plan.monthlySpendingMinor = data.monthlySpendingMinor
        plan.withdrawalRateBP = data.withdrawalRateBP
        plan.monthlyIncomeMinor = data.monthlyIncomeMinor
        plan.savingsFloorBP = data.savingsFloorBP
        plan.illiquidCapBP = data.illiquidCapBP
        plan.usTargetBP = data.usTargetBP
        plan.mixToleranceBP = data.mixToleranceBP
        plan.usesMemberContributions = data.usesMemberContributions
        plan.driftToleranceBP = data.driftToleranceBP
        plan.driftRelativeBP = data.driftRelativeBP
        plan.disabledDiagnosesRaw = data.disabledDiagnosesRaw ?? ""
        plan.contributionOrderRaw = data.contributionOrderRaw ?? ""
        plan.bondReturnBP = data.bondReturnBP ?? 350
        plan.commodityReturnBP = data.commodityReturnBP ?? 300
        plan.createdAt = data.createdAt
        plan.updatedAt = data.updatedAt
    }
}
