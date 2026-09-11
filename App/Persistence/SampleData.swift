import Core
import Foundation
import CoreData

#if DEBUG
/// CI 스크린샷과 미리보기용 가상 데이터.
///
/// **실제 금액·기관명이 아니다.** 저장소에 개인 금융 정보를 커밋하지 않는다는 원칙에 따라
/// 구조만 실제와 같게 두고 숫자는 전부 지어낸 값을 쓴다.
/// 실행 인자 `-seedSampleData` 가 있을 때만 인메모리 저장소에 채운다.
enum SampleData {

    static func seed(into context: NSManagedObjectContext) {
        let dad = Member(context: context, name: "아빠", roleNote: "본인", birthYear: 1984, birthMonth: 3,
                         taxResidency: .korea, colorIndex: 0, sortIndex: 0)
        let mom = Member(context: context, name: "엄마", roleNote: "미국 시민권자", birthYear: 1986, birthMonth: 7,
                         taxResidency: .usa, colorIndex: 1, sortIndex: 1)
        let son = Member(context: context, name: "아들", roleNote: "2022년생", birthYear: 2022, birthMonth: 5,
                         taxResidency: .usa, colorIndex: 2, sortIndex: 2)
        let daughter = Member(context: context, name: "딸", roleNote: "2023년생", birthYear: 2023, birthMonth: 9,
                              taxResidency: .usa, colorIndex: 3, sortIndex: 3)

        // 아빠 — 일반 위탁 · 연금보험 · 전월세보증금 · 마이너스통장
        let dadBrokerage = account("종합계좌", "증권사 A", .general, dad, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 48_200_000, dadBrokerage, 0, context, targetBP: 4_000)
        holding("해외 ETF B", .equity, .etf, "US", .accumulating, .weekly, 26_400_000, dadBrokerage, 1, context, targetBP: 4_000)
        holding("국내 대형주", .equity, .stock, "KR", .frozen, .weekly, 9_100_000, dadBrokerage, 2, context, targetBP: 2_000)

        let dadInsurance = account("연금보험", "보험사 B", .insurance, dad, 1, context)
        holding("해지환급금", .insurance, .other, "KR", .accumulating, .monthly, 19_800_000, dadInsurance, 0, context)

        // 한도가 있는 계좌 둘. 자산 진단의 "어느 계좌부터 채울지" 규칙이 이걸 읽는다.
        // 연금저축은 다 채웠고 IRP 는 남아 있어, 다음 적립을 IRP 로 지목하게 된다.
        // **한도 숫자도 예시다** — 앱은 세법을 따라가지 않는다.
        let dadPension = account("연금저축", "증권사 A", .pensionSavings, dad, 2, context)
        dadPension.annualLimitMinor = 6_000_000
        dadPension.annualContributionMinor = 6_000_000
        holding("TDF 2045", .equity, .fund, "KR", .accumulating, .monthly, 42_000_000, dadPension, 0, context, targetBP: 10_000)

        let dadIRP = account("IRP", "증권사 A", .irp, dad, 3, context)
        dadIRP.annualLimitMinor = 3_000_000
        dadIRP.annualContributionMinor = 1_800_000
        // 만기가 있는 계좌. 1페이지 푸터의 `임박한 만기` 가 이걸 읽는다
        // (docs/08-feedback.md 28번). **날짜도 예시다.**
        dadIRP.maturesOn = Calendar.current.date(byAdding: .day, value: 96, to: .now)
        holding("채권 혼합형", .bond, .fund, "KR", .accumulating, .monthly, 18_500_000, dadIRP, 0, context)

        // 받을 돈 — 종목 자리에 빌려준 사람들이 늘어선다. 비중·목표가 없는
        // 것이 맞는 계좌라, 예외 처리가 화면에 찍히는지 보려고 넣어 둔다
        // (docs/08-feedback.md 19번).
        let dadLent = account("받을 돈", "", .receivable, dad, 4, context)
        holding("지인 A", .receivable, .other, "KR", .accumulating, .fixed,
                5_000_000, dadLent, 0, context)
        holding("지인 B", .receivable, .other, "KR", .accumulating, .fixed,
                3_000_000, dadLent, 1, context)

        let dadLease = account("전월세보증금", "", .leaseDeposit, dad, 5, context)
        holding("보증금", .leaseDeposit, .physical, "KR", .accumulating, .fixed, 100_000_000, dadLease, 0, context)

        let dadLoan = account("마이너스통장", "은행 C", .loan, dad, 6, context)
        holding("사용액", .cash, .cash, "KR", .accumulating, .weekly, 4_500_000, dadLoan, 0, context)

        // 엄마 — 국내 개별주만 (PFIC 회피)
        let momBrokerage = account("일반계좌", "증권사 D", .general, mom, 0, context)
        holding("국내 로봇주", .equity, .stock, "KR", .accumulating, .weekly, 2_000_000, momBrokerage, 0, context)

        // 아들 — 국내 ETF 가 섞여 있어 PFIC 경고가 뜬다
        let sonBrokerage = account("증여계좌", "증권사 D", .general, son, 0, context)
        holding("국내 반도체주", .equity, .stock, "KR", .frozen, .weekly, 24_300_000, sonBrokerage, 0, context, targetBP: 3_000)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_750_000, sonBrokerage, 1, context, targetBP: 4_000)
        holding("국내 지수 ETF", .equity, .etf, "KR", .frozen, .weekly, 3_100_000, sonBrokerage, 2, context, targetBP: 3_000)

        // **같은 이름의 계좌 둘 — 기관만 다르다.** 30번 버그가 났던 모양 그대로라
        // CI 스크린샷에서 두 줄이 제대로 나뉘는지(둘 다 100%가 아닌지) 보인다.
        let sonBrokerageB = account("증여계좌", "증권사 E", .general, son, 1, context)
        holding("해외 ETF B", .equity, .etf, "US", .accumulating, .weekly,
                1_950_000, sonBrokerageB, 0, context)

        // 딸
        let daughterBrokerage = account("증여계좌", "증권사 D", .general, daughter, 0, context)
        holding("국내 바이오주", .equity, .stock, "KR", .accumulating, .weekly, 5_600_000, daughterBrokerage, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_800_000, daughterBrokerage, 1, context)

        seedPastReviews(members: [dad, mom, son, daughter], into: context)

        let plan = Plan(context: context)
        plan.monthlyContributionMinor = 4_100_000
        plan.annualReturnBP = 800
        plan.contributionGrowthBP = 300
        plan.inflationBP = 200
        plan.postRetirementReturnBP = 500
        plan.retirementYear = Calendar.current.component(.year, from: .now) + 23
        plan.targetAmountMinor = 5_900_000_000

        // 진단 기준 — 전부 예시 수치다. 실제 금액이 아니다.
        plan.monthlySpendingMinor = 4_000_000
        plan.monthlyIncomeMinor = 9_000_000
        plan.horizonYear = plan.retirementYear + 35

        // 은퇴 후 소득 — 전부 예시 수치다.
        // 하나는 물가연동(국민연금), 하나는 확정형이라 갈수록 힘이 빠진다.
        let pension = IncomeStream(context: context, label: "국민연금", monthlyAmountMinor: 1_400_000,
                                   startYear: plan.retirementYear + 2, sortIndex: 0)

        let privatePension = IncomeStream(context: context, label: "개인연금 (확정)", monthlyAmountMinor: 600_000,
                                          startYear: plan.retirementYear, sortIndex: 1)
        privatePension.endYear = plan.retirementYear + 20
        privatePension.isInflationLinked = false

        // 유의사항 · 할 일 — 전부 예시다.
        let limitTodo = TodoItem(context: context, title: "연금저축 한도 채우기", category: .limit, sortIndex: 0)
        limitTodo.dueDate = Calendar.current.date(byAdding: .day, value: 26, to: .now)
        limitTodo.repeatsYearly = true
        limitTodo.detail = "12월 말까지 넣어야 올해 세액공제에 들어갑니다."

        let taxTodo = TodoItem(context: context, title: "아이 계좌 해외 ETF 정리 검토", category: .tax, sortIndex: 1)
        taxTodo.detail = "미국 세적이라 한국 상장 ETF 는 PFIC 로 분류됩니다."

        let leaseTodo = TodoItem(context: context, title: "전세 만기 6개월 전 알아보기", category: .deadline, sortIndex: 2)
        leaseTodo.dueDate = Calendar.current.date(byAdding: .day, value: 120, to: .now)

        // 운용 원칙 — **기본 열여섯을 그대로 넣는다.** 1페이지가 가장 꽉 차는
        // 경우라, CI 스크린샷이 "한 장에 들어가나" 를 최악의 조건에서 보여준다
        // (docs/08-feedback.md 24번).
        for (index, title) in DefaultPrinciples.titles.enumerated() {
            _ = Principle(context: context, order: index + 1, title: title)
        }

        // 변경 이력 — 비어 있으면 CI 스크린샷이 빈 화면만 찍어서, 이력이
        // 실제로 그려지는지 확인할 수 없다 (docs/08-feedback.md 29번).
        let logs: [(ChangeKind, String, String, Int)] = [
            (.weeklyEntry, "주간 점검 · 종목 14건", "2억 9,800만 → 3억 800만", 0),
            (.structure, "아들 · 증여계좌 · 해외 ETF B", "종목을 추가했습니다", 2),
            (.planValue, "계획", "월 적립 · 연 기대수익률 을(를) 고쳤습니다", 9),
            // 축하 (88번). 지난달 회고와 변경 이력에 보인다.
            (.milestone, "3억을 넘었습니다", "가족 총자산 3.0억", 21)
        ]
        for (kind, subject, summary, daysAgo) in logs {
            let log = ChangeLog(context: context, kind: kind, subject: subject, summary: summary,
                                actor: kind == .structure ? "엄마" : "아빠")
            log.at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        }

        // 직접 찍은 마일스톤
        // 구성원에게 붙은 마일스톤. 현황판 `인생 이벤트` 줄이 그 해 나이를
        // 함께 적는지 스크린샷으로 본다 (docs/08-feedback.md 32번).
        let college = UserMilestone(context: context, year: Calendar.current.component(.year, from: .now) + 14,
                                    label: "첫째 대학 입학", sortIndex: 0, memberID: son.id)

        let calendar = Calendar.current
        let deposit = CashEvent(context: context,
            date: calendar.date(byAdding: .month, value: 3, to: .now) ?? .now,
            label: "전월세보증금 투자 전환", amountMinor: 100_000_000, sortIndex: 0
        )

        let severance = CashEvent(context: context,
            date: calendar.date(byAdding: .month, value: 18, to: .now) ?? .now,
            label: "퇴직금 유입", amountMinor: 70_000_000, sortIndex: 1
        )
    }

    /// 지난 점검 기록. 연속 기록과 주간 증감이 화면에 실제로 보이게 한다.
    /// 이번 주는 일부러 비워 둬서 "지금 입력" 상태를 확인할 수 있게 한다.
    private static func seedPastReviews(members: [Member], into context: NSManagedObjectContext) {
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

            let session = ReviewSession(context: context, weekAnchor: anchor, totalCount: weeklyCount)
            session.enteredCount = weeklyCount
            session.completedAt = anchor
            session.totalValueMinor = running
            session.previousTotalValueMinor = previous
            // 구성원별 연속 기록(C8)이 화면에 보이게. 두 번째 사람은 지난주를
            // 걸러서 "끊긴" 모양도 함께 찍힌다.
            session.setEnteredMembers(Set(members.enumerated()
                .filter { !($0.offset == 1 && weeksAgo == 1) }
                .map { $0.element.id }))
            // 진단 이력 (A9). 은퇴 필요 자금은 내내 조치, 저축률은 6주 전에
            // 주의에서 지킴으로 — "몇 주째" 와 "바뀐 주" 가 둘 다 찍히게.
            session.diagnosisRaw = [
                "retirementTarget=act",
                "savingsRate=" + (weeksAgo > 6 ? "watch" : "pass"),
                "realEstateShare=pass",
                "countryMix=watch",
                "targetWeights=act",
            ].joined(separator: ",")

            let snapshot = Snapshot(context: context, weekAnchor: anchor,
                                    netWorthMinor: running,
                                    investableMinor: running - 100_000_000,
                                    liabilitiesMinor: 4_500_000)

            // 종목별 지난 값 (A3). 지금 값에서 주마다 조금씩 거슬러 — 오르내림이
            // 섞이게 홀짝으로 방향을 바꾼다. 고정 종목은 그대로.
            for member in members {
                for account in member.sortedAccounts {
                    for (position, holding) in account.sortedHoldings.enumerated() {
                        let line = HoldingRecord(context: context)
                        line.weekAnchor = anchor
                        line.holdingID = holding.id
                        line.holdingName = holding.name
                        line.accountName = account.name
                        line.memberID = member.id
                        let drift = holding.cadence == .fixed ? 0
                            : holding.valueMinor / 50 * weeksAgo * (position % 2 == 0 ? -1 : 1)
                            + holding.valueMinor / 200 * (weeksAgo % 3)
                        line.valueMinor = holding.valueMinor + drift
                    }
                }
            }

            var assigned = 0
            for (position, member) in members.enumerated() {
                let isLast = position == members.count - 1
                let value = isLast
                    ? running - assigned
                    : running * weights[position % weights.count] / totalWeight
                assigned += value

                let line = SnapshotLine(context: context, memberID: member.id, memberName: member.name,
                                        valueMinor: value, sortIndex: position)
                line.snapshot = snapshot
            }
        }
    }

    @discardableResult
    private static func account(_ name: String, _ institution: String, _ kind: AccountKind,
                                _ owner: Member, _ sortIndex: Int,
                                _ context: NSManagedObjectContext) -> Account {
        let account = Account(context: context, name: name, institution: institution, kind: kind,
                              owner: owner, sortIndex: sortIndex)
        return account
    }

    /// `targetBP` 는 **그 계좌 안에서**의 목표다. 한 계좌 안 종목들의 합이
    /// 100%가 되도록 적는다 — 그래야 화면의 `목표 합` 이 초록으로 선다.
    /// 일부러 몇 계좌는 비워 둔다. `목표 미완` 배지가 찍히는지 봐야 하기 때문이다.
    private static func holding(_ name: String, _ assetClass: AssetClass,
                                _ instrumentType: InstrumentType, _ country: String,
                                _ status: HoldingStatus, _ cadence: EntryCadence,
                                _ valueMinor: Int, _ account: Account, _ sortIndex: Int,
                                _ context: NSManagedObjectContext, targetBP: Int? = nil) {
        let holding = Holding(context: context, name: name, assetClass: assetClass, instrumentType: instrumentType,
                              listingCountryCode: country, status: status, cadence: cadence,
                              valueMinor: valueMinor, account: account, sortIndex: sortIndex)
        holding.targetWeightBP = targetBP
        // 지난주 값이 있어야 증감이 화면에 보인다. 오른 것과 내린 것을 섞는다.
        holding.lastEnteredValueMinor = sortIndex % 2 == 0
            ? valueMinor - valueMinor / 40      // 이번 주 상승
            : valueMinor + valueMinor / 60      // 이번 주 하락
        holding.lastEnteredAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)
    }
}
#endif
