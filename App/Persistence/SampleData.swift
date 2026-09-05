import Core
import Foundation
import SwiftData

#if DEBUG
/// CI 스크린샷과 미리보기용 가상 데이터.
///
/// **실제 금액·기관명이 아니다.** 저장소에 개인 금융 정보를 커밋하지 않는다는 원칙에 따라
/// 구조만 실제와 같게 두고 숫자는 전부 지어낸 값을 쓴다.
/// 실행 인자 `-seedSampleData` 가 있을 때만 인메모리 저장소에 채운다.
enum SampleData {

    static func seed(into context: ModelContext) {
        let dad = Member(name: "아빠", roleNote: "본인", birthYear: 1984, birthMonth: 3,
                         taxResidency: .korea, colorIndex: 0, sortIndex: 0)
        let mom = Member(name: "엄마", roleNote: "미국 시민권자", birthYear: 1986, birthMonth: 7,
                         taxResidency: .usa, colorIndex: 1, sortIndex: 1)
        let son = Member(name: "아들", roleNote: "2022년생", birthYear: 2022, birthMonth: 5,
                         taxResidency: .usa, colorIndex: 2, sortIndex: 2)
        let daughter = Member(name: "딸", roleNote: "2023년생", birthYear: 2023, birthMonth: 9,
                              taxResidency: .usa, colorIndex: 3, sortIndex: 3)
        [dad, mom, son, daughter].forEach(context.insert)

        // 아빠 — 일반 위탁 · 연금보험 · 전세보증금 · 마이너스통장
        let dadBrokerage = account("종합계좌", "증권사 A", .general, dad, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 48_200_000, dadBrokerage, 0, context)
        holding("해외 ETF B", .equity, .etf, "US", .accumulating, .weekly, 26_400_000, dadBrokerage, 1, context)
        holding("국내 대형주", .equity, .stock, "KR", .frozen, .weekly, 9_100_000, dadBrokerage, 2, context)

        let dadInsurance = account("연금보험", "보험사 B", .insurance, dad, 1, context)
        holding("해지환급금", .insurance, .other, "KR", .accumulating, .monthly, 19_800_000, dadInsurance, 0, context)

        // 한도가 있는 계좌 둘. 자산 진단의 "어느 계좌부터 채울지" 규칙이 이걸 읽는다.
        // 연금저축은 다 채웠고 IRP 는 남아 있어, 다음 적립을 IRP 로 지목하게 된다.
        // **한도 숫자도 예시다** — 앱은 세법을 따라가지 않는다.
        let dadPension = account("연금저축", "증권사 A", .pensionSavings, dad, 2, context)
        dadPension.annualLimitMinor = 6_000_000
        dadPension.annualContributionMinor = 6_000_000
        holding("TDF 2045", .equity, .fund, "KR", .accumulating, .monthly, 42_000_000, dadPension, 0, context)

        let dadIRP = account("IRP", "증권사 A", .irp, dad, 3, context)
        dadIRP.annualLimitMinor = 3_000_000
        dadIRP.annualContributionMinor = 1_800_000
        holding("채권 혼합형", .bond, .fund, "KR", .accumulating, .monthly, 18_500_000, dadIRP, 0, context)

        let dadLease = account("전세보증금", "", .leaseDeposit, dad, 4, context)
        holding("보증금", .realEstate, .physical, "KR", .accumulating, .fixed, 100_000_000, dadLease, 0, context)

        let dadLoan = account("마이너스통장", "은행 C", .loan, dad, 5, context)
        holding("사용액", .cash, .cash, "KR", .accumulating, .weekly, 4_500_000, dadLoan, 0, context)

        // 엄마 — 국내 개별주만 (PFIC 회피)
        let momBrokerage = account("일반계좌", "증권사 D", .general, mom, 0, context)
        holding("국내 로봇주", .equity, .stock, "KR", .accumulating, .weekly, 2_000_000, momBrokerage, 0, context)

        // 아들 — 국내 ETF 가 섞여 있어 PFIC 경고가 뜬다
        let sonBrokerage = account("증여계좌", "증권사 D", .general, son, 0, context)
        holding("국내 반도체주", .equity, .stock, "KR", .frozen, .weekly, 24_300_000, sonBrokerage, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_750_000, sonBrokerage, 1, context)
        holding("국내 지수 ETF", .equity, .etf, "KR", .frozen, .weekly, 3_100_000, sonBrokerage, 2, context)

        // 딸
        let daughterBrokerage = account("증여계좌", "증권사 D", .general, daughter, 0, context)
        holding("국내 바이오주", .equity, .stock, "KR", .accumulating, .weekly, 5_600_000, daughterBrokerage, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_800_000, daughterBrokerage, 1, context)

        seedPastReviews(members: [dad, mom, son, daughter], into: context)

        let plan = Plan()
        plan.monthlyContributionMinor = 4_100_000
        plan.annualReturnBP = 800
        plan.contributionGrowthBP = 300
        plan.inflationBP = 200
        plan.retirementYear = Calendar.current.component(.year, from: .now) + 23
        plan.targetAmountMinor = 5_900_000_000

        // 진단 기준 — 전부 예시 수치다. 실제 금액이 아니다.
        plan.monthlySpendingMinor = 4_000_000
        plan.monthlyIncomeMinor = 9_000_000
        plan.horizonYear = plan.retirementYear + 35

        // 은퇴 후 소득 — 전부 예시 수치다.
        // 하나는 물가연동(국민연금), 하나는 확정형이라 갈수록 힘이 빠진다.
        let pension = IncomeStream(label: "국민연금", monthlyAmountMinor: 1_400_000,
                                   startYear: plan.retirementYear + 2, sortIndex: 0)
        context.insert(pension)

        let privatePension = IncomeStream(label: "개인연금 (확정)", monthlyAmountMinor: 600_000,
                                          startYear: plan.retirementYear, sortIndex: 1)
        privatePension.endYear = plan.retirementYear + 20
        privatePension.isInflationLinked = false
        context.insert(privatePension)
        context.insert(plan)

        let calendar = Calendar.current
        let deposit = CashEvent(
            date: calendar.date(byAdding: .month, value: 3, to: .now) ?? .now,
            label: "전세보증금 투자 전환", amountMinor: 100_000_000, sortIndex: 0
        )
        context.insert(deposit)

        let severance = CashEvent(
            date: calendar.date(byAdding: .month, value: 18, to: .now) ?? .now,
            label: "퇴직금 유입", amountMinor: 70_000_000, sortIndex: 1
        )
        context.insert(severance)
    }

    /// 지난 점검 기록. 연속 기록과 주간 증감이 화면에 실제로 보이게 한다.
    /// 이번 주는 일부러 비워 둬서 "지금 입력" 상태를 확인할 수 있게 한다.
    private static func seedPastReviews(members: [Member], into context: ModelContext) {
        let thisWeek = ReviewWeek.anchor(for: .now)
        let calendar = Calendar.current
        let weeklyCount = members
            .flatMap { $0.sortedAccounts }
            .flatMap { $0.sortedHoldings }
            .filter { $0.cadence != .fixed }
            .count
        // 구성원별 비중. 마지막 사람이 나머지를 받아 합이 총액과 정확히 맞는다.
        let weights = [1990, 20, 292, 74]
        let totalWeight = weights.reduce(0, +)
        var running = 231_400_000

        for weeksAgo in stride(from: 12, through: 1, by: -1) {
            guard let anchor = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisWeek) else { continue }
            let previous = running
            running += 500_000 + weeksAgo * 37_000

            let session = ReviewSession(weekAnchor: anchor, totalCount: weeklyCount)
            session.enteredCount = weeklyCount
            session.completedAt = anchor
            session.totalValueMinor = running
            session.previousTotalValueMinor = previous
            context.insert(session)

            let snapshot = Snapshot(weekAnchor: anchor,
                                    netWorthMinor: running,
                                    investableMinor: running - 100_000_000,
                                    liabilitiesMinor: 4_500_000)
            context.insert(snapshot)

            var assigned = 0
            for (position, member) in members.enumerated() {
                let isLast = position == members.count - 1
                let value = isLast
                    ? running - assigned
                    : running * weights[position % weights.count] / totalWeight
                assigned += value

                let line = SnapshotLine(memberID: member.id, memberName: member.name,
                                        valueMinor: value, sortIndex: position)
                line.snapshot = snapshot
                context.insert(line)
            }
        }
    }

    @discardableResult
    private static func account(_ name: String, _ institution: String, _ kind: AccountKind,
                                _ owner: Member, _ sortIndex: Int,
                                _ context: ModelContext) -> Account {
        let account = Account(name: name, institution: institution, kind: kind,
                              owner: owner, sortIndex: sortIndex)
        context.insert(account)
        return account
    }

    private static func holding(_ name: String, _ assetClass: AssetClass,
                                _ instrumentType: InstrumentType, _ country: String,
                                _ status: HoldingStatus, _ cadence: EntryCadence,
                                _ valueMinor: Int, _ account: Account, _ sortIndex: Int,
                                _ context: ModelContext) {
        let holding = Holding(name: name, assetClass: assetClass, instrumentType: instrumentType,
                              listingCountryCode: country, status: status, cadence: cadence,
                              valueMinor: valueMinor, account: account, sortIndex: sortIndex)
        // 지난주 값이 있어야 증감이 화면에 보인다. 오른 것과 내린 것을 섞는다.
        holding.lastEnteredValueMinor = sortIndex % 2 == 0
            ? valueMinor - valueMinor / 40      // 이번 주 상승
            : valueMinor + valueMinor / 60      // 이번 주 하락
        holding.lastEnteredAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        context.insert(holding)
    }
}
#endif
