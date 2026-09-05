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
    /// 은퇴 목표 연도. 궤적은 여기서 멈춘다.
    var retirementYear: Int = Calendar.current.component(.year, from: .now) + 23

    var monthlyContributionMinor: Int = 0
    /// 연 기대수익률 (basis point). 800 = 8%
    var annualReturnBP: Int = 800
    /// 적립액의 연 증가율. 연봉 상승률에 맞춘다.
    var contributionGrowthBP: Int = 0
    var inflationBP: Int = 200
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
        calendar: Calendar = .current
    ) -> ProjectionResult {
        Projection.run(projectionInput(from: balance, cashEvents: cashEvents, calendar: calendar),
                       calendar: calendar)
    }

    /// 계산 직전의 입력. 시뮬레이션은 이걸 받아 손잡이만 바꿔 끼운다.
    ///
    /// `@Model` 은 `Sendable` 이 아니지만 `ProjectionInput` 은 값 타입이라
    /// 어디로든 넘길 수 있다. 시뮬레이션이 Plan 을 들고 다니지 않는 이유다.
    func projectionInput(
        from balance: Money,
        cashEvents: [CashEvent] = [],
        calendar: Calendar = .current
    ) -> ProjectionInput {
        let now = calendar.startOfDay(for: .now)
        let end = calendar.date(from: DateComponents(year: retirementYear, month: 12, day: 31)) ?? now
        let pending = cashEvents
            .filter { !$0.isAlreadyReflected && $0.date > now }
            .map { CashEventInput(date: $0.date, amount: $0.amount, label: $0.label) }

        return ProjectionInput(
            startDate: now,
            endDate: max(end, now),
            startingBalance: balance,
            monthlyContribution: monthlyContribution,
            annualReturn: annualReturn,
            annualContributionGrowth: contributionGrowth,
            inflation: inflation,
            cashEvents: pending,
            targetAmount: targetAmountMinor > 0 ? targetAmount : nil
        )
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
        calendar: Calendar = .current
    ) -> DiagnosticsInput {
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
            monthlyContribution: monthlyContribution,
            savingsFloor: savingsFloor,
            annualReturn: annualReturn,
            illiquidCap: illiquidCap,
            usTarget: usTarget,
            mixTolerance: mixTolerance,
            yearsToRetirement: yearsToRetirement,
            projectedAtRetirement: projection?.last?.nominal,
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
