import Core
import Foundation
import SwiftData

/// 계획의 가정. 가구당 하나만 둔다.
///
/// 지금은 가구 전체를 하나의 숫자로 굴린다. 구성원별 적립 계획·연금·목돈 이벤트는
/// M2 후반에 세분화한다. 먼저 궤적 한 줄을 끝까지 그려 보는 것이 순서다.
@Model
final class Plan {
    var id: UUID = UUID()
    var title: String = "우리 가족 노후자금 준비"
    /// 계획을 세운 해. 로드맵 타임라인의 왼쪽 끝.
    var startYear: Int = Calendar.current.component(.year, from: .now)
    /// 계획을 시작한 날. "언제부터 체계적으로 관리했는지" 를 1페이지에 적는다.
    /// 연도만으로는 그걸 알 수 없다 (docs/08-feedback.md 10번).
    var startedOn: Date?
    /// 기준 시점 라벨 — `2026.08 기준 · 이사 후 자산` 같은 선언.
    /// **같은 자산을 두 번 세지 않기 위한 것**이라 1페이지 머리에 크게 적는다.
    var asOfNote: String = ""
    /// 1페이지 맨 아래 한 줄. `계획은 끝났다. 이제는 시간이 일한다.`
    var declaration: String = ""
    /// 은퇴 목표 연도. 궤적은 여기서 멈춘다.
    var retirementYear: Int = Calendar.current.component(.year, from: .now) + 23

    var monthlyContributionMinor: Int = 0
    /// 연 기대수익률 (basis point). 800 = 8%
    var annualReturnBP: Int = 800
    /// 적립액의 연 증가율. 연봉 상승률에 맞춘다.
    var contributionGrowthBP: Int = 0
    var inflationBP: Int = 200
    /// 저수익 자산의 기대수익률. 예적금·연금보험이 여기 붙는다.
    /// 계좌마다 따로 적으면 그 값이 이긴다 (`Account.expectedReturnBP`).
    var lowYieldReturnBP: Int = 200
    /// 부동산 기대수익률. 기본은 물가상승률과 같게 둔다.
    var realEstateReturnBP: Int = 200
    /// 은퇴 시점 목표 금액. 0이면 목표선을 그리지 않는다.
    var targetAmountMinor: Int = 0

    // MARK: 진단 기준
    //
    // 전부 사용자가 고칠 수 있는 값이다. 기본값은 흔히 쓰는 수치일 뿐
    // 정답이 아니다. CloudKit 제약 때문에 모두 기본값을 갖는다 (ADR-0001).

    /// 은퇴 후 한 달 생활비. 0이면 은퇴 필요 자금을 판단하지 않는다.
    var monthlySpendingMinor: Int = 0
    /// 인출률. 400 = 4% (4% 규칙).
    var withdrawalRateBP: Int = 400
    /// 세후 월 소득. 저축률 계산에만 쓴다.
    var monthlyIncomeMinor: Int = 0
    /// 최소 저축률. 1000 = 10%.
    var savingsFloorBP: Int = 1_000
    /// 부동산 · 전세보증금 비중 상한. 3500 = 35%.
    var illiquidCapBP: Int = 3_500
    /// 미국 목표 비중. 6000 = 60%.
    var usTargetBP: Int = 6_000
    /// 목표에서 이만큼 벗어나도 조치로 보지 않는다. 500 = 5%p.
    var mixToleranceBP: Int = 500

    /// 월 적립을 구성원별로 나눠 넣는가. 켜면 Member 의 몫을 합해서 쓴다.
    ///
    /// 합계 하나로도 궤적은 똑같이 그려진다. 나누는 이유는 "누가 얼마를 넣고
    /// 있는가"가 가족이 함께 보는 화면에서 의미를 갖기 때문이다.
    var usesMemberContributions: Bool = false

    /// 궤적을 어디까지 그릴 것인가. 은퇴 이후 인출 구간의 끝이다.
    /// 기본은 은퇴 후 35년 — 65세 은퇴면 100세까지 본다.
    var horizonYear: Int = Calendar.current.component(.year, from: .now) + 23 + 35

    var createdAt: Date = Date.now

    init() {}
}

/// 특정 시점의 큰 자금 이동. 전세보증금 전환, 퇴직금 유입, 주택 구입.
@Model
final class CashEvent {
    var id: UUID = UUID()
    var date: Date = Date.now
    var label: String = ""
    /// 부호로 방향을 표현한다. 양수는 유입, 음수는 유출.
    var amountMinor: Int = 0
    /// 이미 현재 잔고에 반영된 이벤트. 예측에서 빼야 두 번 세지 않는다.
    ///
    /// 1페이지의 "이 표의 모든 금액은 이사 완료 후 기준 — 중복 계산 방지" 가
    /// 바로 이 문제였다.
    var isAlreadyReflected: Bool = false
    var note: String = ""
    var sortIndex: Int = 0

    init(date: Date = .now, label: String = "", amountMinor: Int = 0, sortIndex: Int = 0) {
        self.date = date
        self.label = label
        self.amountMinor = amountMinor
        self.sortIndex = sortIndex
    }
}

/// 은퇴 후 들어오는 소득. 국민연금 · 퇴직연금 · 개인연금 · 임대소득.
///
/// **금액은 오늘 돈 기준으로 적는다.** "65세부터 월 150만원"의 150만원은
/// 지금 물가로 말한 것이지 20년 뒤의 액면가가 아니다.
@Model
final class IncomeStream {
    var id: UUID = UUID()
    var label: String = ""
    /// 오늘 돈 기준 월 수령액.
    var monthlyAmountMinor: Int = 0
    var startYear: Int = Calendar.current.component(.year, from: .now) + 20
    /// 0이면 종신.
    var endYear: Int = 0
    /// 물가에 연동되는가. 국민연금은 연동되고 확정형 개인연금은 안 된다.
    /// 30년이면 이 차이가 결과를 절반으로 가른다.
    var isInflationLinked: Bool = true
    var sortIndex: Int = 0

    init(label: String = "", monthlyAmountMinor: Int = 0, startYear: Int? = nil,
         sortIndex: Int = 0) {
        self.label = label
        self.monthlyAmountMinor = monthlyAmountMinor
        self.startYear = startYear ?? (Calendar.current.component(.year, from: .now) + 20)
        self.sortIndex = sortIndex
    }
}

extension IncomeStream {
    var monthlyAmount: Money { Money(minorUnits: monthlyAmountMinor, currency: .krw) }

    var input: IncomeStreamInput {
        IncomeStreamInput(
            label: label,
            monthlyAmount: monthlyAmount,
            startYear: startYear,
            endYear: endYear > 0 ? endYear : nil,
            isInflationLinked: isInflationLinked
        )
    }
}

extension CashEvent {
    var amount: Money { Money(minorUnits: amountMinor, currency: .krw) }
    var isInflow: Bool { amountMinor >= 0 }
}

extension Plan {
    var annualReturn: Ratio { Ratio(basisPoints: annualReturnBP) }
    var withdrawalRate: Ratio { Ratio(basisPoints: withdrawalRateBP) }
    var savingsFloor: Ratio { Ratio(basisPoints: savingsFloorBP) }
    var illiquidCap: Ratio { Ratio(basisPoints: illiquidCapBP) }
    var usTarget: Ratio { Ratio(basisPoints: usTargetBP) }
    var mixTolerance: Ratio { Ratio(basisPoints: mixToleranceBP) }
    var monthlySpending: Money { Money(minorUnits: monthlySpendingMinor, currency: .krw) }
    var monthlyIncome: Money { Money(minorUnits: monthlyIncomeMinor, currency: .krw) }
    var contributionGrowth: Ratio { Ratio(basisPoints: contributionGrowthBP) }
    var inflation: Ratio { Ratio(basisPoints: inflationBP) }
    var lowYieldReturn: Ratio { Ratio(basisPoints: lowYieldReturnBP) }
    var realEstateReturn: Ratio { Ratio(basisPoints: realEstateReturnBP) }
    var monthlyContribution: Money { Money(minorUnits: monthlyContributionMinor, currency: .krw) }
    var targetAmount: Money { Money(minorUnits: targetAmountMinor, currency: .krw) }

    var yearsToRetirement: Int {
        max(retirementYear - Calendar.current.component(.year, from: .now), 0)
    }

    /// 오늘 잔고에서 은퇴 시점까지 굴린다.
    ///
    /// 이미 반영된 목돈은 넣지 않는다. 현재 잔고에 이미 들어 있는데 또 더하면
    /// 두 번 세는 셈이 된다.
    func projection(
        from balance: Money,
        cashEvents: [CashEvent] = [],
        incomes: [IncomeStream] = [],
        members: [Member] = [],
        calendar: Calendar = .current
    ) -> ProjectionResult {
        Projection.run(
            projectionInput(from: balance, cashEvents: cashEvents, incomes: incomes,
                            members: members, calendar: calendar),
            calendar: calendar
        )
    }

    /// 실제로 굴릴 월 적립액. 구성원별로 나눠 넣고 있으면 그 합이다.
    func effectiveMonthlyContribution(members: [Member]) -> Money {
        guard usesMemberContributions else { return monthlyContribution }
        return Money(minorUnits: members.reduce(0) { $0 + $1.monthlyContributionMinor },
                     currency: .krw)
    }

    /// 계산 직전의 입력. 시뮬레이션은 이걸 받아 손잡이만 바꿔 끼운다.
    ///
    /// `@Model` 은 `Sendable` 이 아니지만 `ProjectionInput` 은 값 타입이라
    /// 어디로든 넘길 수 있다. 시뮬레이션이 Plan 을 들고 다니지 않는 이유다.
    func projectionInput(
        from balance: Money,
        cashEvents: [CashEvent] = [],
        incomes: [IncomeStream] = [],
        members: [Member] = [],
        calendar: Calendar = .current
    ) -> ProjectionInput {
        let now = calendar.startOfDay(for: .now)
        let retirement = Plan.endDate(retirementYear: retirementYear, notBefore: now, calendar: calendar)
        // 은퇴 후 생활비를 넣지 않았으면 은퇴 시점에서 멈춘다. 인출을 가정하지
        // 않는 궤적에 20년을 더 그려 봐야 그냥 계속 오르는 선일 뿐이다.
        let horizon = monthlySpendingMinor > 0
            ? Plan.endDate(retirementYear: max(horizonYear, retirementYear),
                           notBefore: retirement, calendar: calendar)
            : retirement
        let pending = cashEvents
            .filter { !$0.isAlreadyReflected && $0.date > now }
            .map { CashEventInput(date: $0.date, amount: $0.amount, label: $0.label) }

        return ProjectionInput(
            startDate: now,
            endDate: horizon,
            buckets: buckets(of: members, total: balance),
            monthlyContribution: effectiveMonthlyContribution(members: members),
            annualReturn: annualReturn,
            annualContributionGrowth: contributionGrowth,
            inflation: inflation,
            cashEvents: pending,
            targetAmount: targetAmountMinor > 0 ? targetAmount : nil,
            annualIncome: Money(minorUnits: monthlyIncomeMinor * 12, currency: .krw),
            retirementDate: retirement,
            monthlyRetirementSpending: monthlySpending,
            incomes: incomes.sorted { $0.sortIndex < $1.sortIndex }.map(\.input)
        )
    }

    /// 순자산을 **자라는 속도별로 나눈다.**
    ///
    /// 예전에는 순자산 전액을 연 8% 로 굴렸다. 그래서 전세보증금 2억이 23년 뒤
    /// 궤적에서 11.8억이 됐다 — 실제로는 2억 그대로인 돈인데도
    /// (docs/08-feedback.md 11번).
    ///
    /// 수익률이 같은 계좌끼리 한 덩어리로 묶는다. 계좌마다 금리를 따로 적으면
    /// 그만큼 덩어리가 늘어나는데, 예금 몇 개 수준이라 문제되지 않는다.
    func buckets(of members: [Member], total: Money) -> [BalanceBucket] {
        struct Key: Hashable { let profile: ReturnProfile; let bp: Int }
        var sums: [Key: Int] = [:]

        for member in members {
            for account in member.sortedAccounts where !account.isArchived {
                let value = account.sortedHoldings.reduce(0) { $0 + $1.valueMinor }
                guard value != 0 else { continue }
                let profile = account.kind.returnProfile
                let key = Key(profile: profile,
                              bp: account.expectedReturnBP ?? defaultReturnBP(for: profile))
                // 부채는 음수로 담는다. 그래야 덩어리의 합이 순자산과 맞는다.
                sums[key, default: 0] += account.kind.isLiability ? -value : value
            }
        }

        var buckets = sums
            .map { BalanceBucket(profile: $0.key.profile,
                                 amount: Money(minorUnits: $0.value, currency: .krw),
                                 annualReturn: Ratio(basisPoints: $0.key.bp)) }
            .sorted {
                ($0.profile.drawdownOrder, $0.annualReturn.basisPoints)
                    < ($1.profile.drawdownOrder, $1.annualReturn.basisPoints)
            }

        // 적립과 목돈이 들어갈 자리가 반드시 있어야 한다. 투자자산이 하나도
        // 없으면(전세보증금만 있는 초기 상태 등) 빈 덩어리를 만들어 둔다.
        if !buckets.contains(where: { $0.profile == .investment }) {
            buckets.insert(BalanceBucket(profile: .investment, amount: .zero(.krw),
                                         annualReturn: annualReturn), at: 0)
        }

        // 덩어리의 합이 화면의 순자산과 어긋나면 **화면이 거짓말을 한다.**
        // 소유자가 없는 계좌처럼 합계에 안 잡히는 경우가 있으므로 차액을
        // 투자자산에 맞춰 넣는다.
        let sum = buckets.dropFirst().reduce(buckets[0].amount) { $0 + $1.amount }
        let gap = total - sum
        if !gap.isZero, let index = buckets.firstIndex(where: { $0.profile == .investment }) {
            buckets[index].amount += gap
        }
        return buckets
    }

    private func defaultReturnBP(for profile: ReturnProfile) -> Int {
        switch profile {
        case .investment: return annualReturnBP
        case .lowYield: return lowYieldReturnBP
        case .realEstate: return realEstateReturnBP
        case .fixed: return 0
        }
    }

    /// 은퇴 연도만 바꾼 종료 시점. 시뮬레이션에서 기간 손잡이가 쓴다.
    static func endDate(retirementYear: Int, notBefore start: Date,
                        calendar: Calendar = .current) -> Date {
        let end = calendar.date(from: DateComponents(year: retirementYear, month: 12, day: 31)) ?? start
        return max(end, start)
    }

    /// 진단에 넘길 입력을 만든다.
    ///
    /// `@Model` 은 여기서 끝난다 — 나가는 것은 값 타입뿐이라 계산이 영속 계층을
    /// 모르고, 시뮬레이터 없이 테스트된다 (ADR-0002).
    func diagnosticsInput(
        rollup: Rollup,
        accounts: [Account],
        projection: ProjectionResult?,
        members: [Member] = [],
        calendar: Calendar = .current
    ) -> DiagnosticsInput {
        // 진단의 "은퇴 시점 예상"은 궤적의 끝이 아니라 **은퇴 시점**이어야 한다.
        // 인출 구간까지 그리기 시작하면서 끝값이 은퇴 후 30년 뒤 잔고가 됐다.
        let atRetirement = projection?.point(inYear: retirementYear, calendar: calendar)?.nominal
            ?? projection?.last?.nominal
        // 부동산 · 전세보증금 = 자산 − 투자자산.
        // countsAsInvestable 이 false 인 것들이 정확히 이 몫이다.
        let illiquid = rollup.assets - rollup.investable
        let year = calendar.component(.year, from: .now)

        return DiagnosticsInput(
            netWorth: rollup.netWorth,
            investable: rollup.investable,
            illiquid: illiquid,
            byCountry: rollup.byCountry,
            monthlySpending: monthlySpending,
            withdrawalRate: withdrawalRate,
            monthlyIncome: monthlyIncome,
            monthlyContribution: effectiveMonthlyContribution(members: members),
            savingsFloor: savingsFloor,
            annualReturn: annualReturn,
            illiquidCap: illiquidCap,
            usTarget: usTarget,
            mixTolerance: mixTolerance,
            yearsToRetirement: yearsToRetirement,
            projectedAtRetirement: atRetirement,
            doublingYear: projection?.milestone(.doubled)?.year,
            currentYear: year,
            limitAccounts: accounts
                .filter { $0.kind.hasContributionLimit }
                .map {
                    LimitAccountInput(
                        kind: $0.kind,
                        name: $0.name,
                        contributedThisYear: Money(minorUnits: $0.annualContributionMinor, currency: .krw),
                        annualLimit: Money(minorUnits: $0.annualLimitMinor, currency: .krw)
                    )
                }
        )
    }

    /// 저장소에 하나뿐인 계획을 꺼내고, 없으면 만든다.
    static func current(in context: ModelContext) -> Plan {
        if let existing = (try? context.fetch(FetchDescriptor<Plan>()))?.first {
            return existing
        }
        let plan = Plan()
        context.insert(plan)
        return plan
    }
}
