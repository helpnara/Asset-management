import Foundation
import Testing
@testable import Core

/// 진단은 "숫자를 만드는" 규칙과 "상태를 가르는" 규칙이 섞여 있다.
/// 숫자는 파이썬으로 대조한 값을 못 박고, 상태는 경계 양쪽을 눌러 확인한다.
@Suite("Diagnostics — 자산 진단")
struct DiagnosticsTests {

    private func won(_ value: Int) -> Money { Money(value, currency: .krw) }

    private func input(
        netWorth: Int = 1_000_000_000,
        investable: Int = 700_000_000,
        illiquid: Int = 300_000_000,
        us: Int = 420_000_000,
        kr: Int = 280_000_000,
        monthlySpending: Int = 4_000_000,
        withdrawalBP: Int = 400,
        monthlyIncome: Int = 8_000_000,
        monthlyContribution: Int = 2_000_000,
        savingsFloorBP: Int = 1_000,
        returnBP: Int = 800,
        illiquidCapBP: Int = 3_500,
        usTargetBP: Int = 6_000,
        toleranceBP: Int = 500,
        yearsToRetirement: Int = 23,
        projected: Int? = nil,
        doublingYear: Int? = nil,
        accounts: [LimitAccountInput] = []
    ) -> DiagnosticsInput {
        DiagnosticsInput(
            netWorth: won(netWorth),
            investable: won(investable),
            illiquid: won(illiquid),
            byCountry: ["US": won(us), "KR": won(kr)],
            monthlySpending: won(monthlySpending),
            withdrawalRate: Ratio(basisPoints: withdrawalBP),
            monthlyIncome: won(monthlyIncome),
            monthlyContribution: won(monthlyContribution),
            savingsFloor: Ratio(basisPoints: savingsFloorBP),
            annualReturn: Ratio(basisPoints: returnBP),
            illiquidCap: Ratio(basisPoints: illiquidCapBP),
            usTarget: Ratio(basisPoints: usTargetBP),
            mixTolerance: Ratio(basisPoints: toleranceBP),
            yearsToRetirement: yearsToRetirement,
            projectedAtRetirement: projected.map(won),
            doublingYear: doublingYear,
            currentYear: 2026,
            limitAccounts: accounts
        )
    }

    // MARK: - 1) 4% 규칙

    @Test("필요 자금은 연 생활비를 인출률로 나눈 값이다")
    func requiredNestEgg() {
        // 월 400만 → 연 4,800만. 4%면 12억, 3.5%면 13.7억, 3%면 16억.
        // 25배를 상수로 박으면 인출률을 바꿀 수 없다.
        #expect(Diagnostics.requiredNestEgg(monthlySpending: won(4_000_000),
                                            withdrawalRate: Ratio(basisPoints: 400))
                == won(1_200_000_000))
        #expect(Diagnostics.requiredNestEgg(monthlySpending: won(4_000_000),
                                            withdrawalRate: Ratio(basisPoints: 350))
                == won(1_371_428_571))
        #expect(Diagnostics.requiredNestEgg(monthlySpending: won(4_000_000),
                                            withdrawalRate: Ratio(basisPoints: 300))
                == won(1_600_000_000))
    }

    @Test("생활비나 인출률이 없으면 계산하지 않는다")
    func requiredNestEggMissing() {
        #expect(Diagnostics.requiredNestEgg(monthlySpending: won(0),
                                            withdrawalRate: Ratio(basisPoints: 400)) == nil)
        #expect(Diagnostics.requiredNestEgg(monthlySpending: won(4_000_000),
                                            withdrawalRate: .zero) == nil)
    }

    @Test("판단은 지금 잔고가 아니라 은퇴 시점 예상으로 한다")
    func retirementJudgedOnProjection() {
        // 지금 10억은 12억에 못 미치지만 아직 은퇴하지 않았다.
        // 여기서 겁을 주면 규칙이 무의미해진다.
        let enough = Diagnostics.run(input(projected: 1_500_000_000))
        #expect(enough.diagnosis(.retirementTarget)?.status == .pass)

        let short = Diagnostics.run(input(projected: 600_000_000))
        #expect(short.diagnosis(.retirementTarget)?.status == .act)

        // 90% 를 넘기면 조치가 아니라 주의다. 12억의 90%는 10.8억.
        let close = Diagnostics.run(input(projected: 1_100_000_000))
        #expect(close.diagnosis(.retirementTarget)?.status == .watch)
    }

    @Test("예측이 없으면 모른다고 한다")
    func retirementWithoutProjection() {
        #expect(Diagnostics.run(input()).diagnosis(.retirementTarget)?.status == .unknown)
    }

    @Test("생활비를 안 넣으면 은퇴 필요 자금을 판단하지 않는다")
    func retirementWithoutSpending() {
        let result = Diagnostics.run(input(monthlySpending: 0, projected: 5_000_000_000))
        #expect(result.diagnosis(.retirementTarget)?.status == .unknown)
    }

    // MARK: - 2) 부동산 비중

    @Test("부동산 비중은 상한의 90%부터 미리 알린다")
    func realEstateThresholds() {
        // 상한 35%. 부동산은 하루아침에 못 줄이므로 닿기 전에 알린다.
        #expect(Diagnostics.run(input(illiquid: 300_000_000))       // 30.0%
                .diagnosis(.realEstateShare)?.status == .pass)
        #expect(Diagnostics.run(input(illiquid: 320_000_000))       // 32.0% → 상한의 91%
                .diagnosis(.realEstateShare)?.status == .watch)
        #expect(Diagnostics.run(input(illiquid: 400_000_000))       // 40.0%
                .diagnosis(.realEstateShare)?.status == .act)
    }

    @Test("자산이 없으면 비중을 판단하지 않는다")
    func realEstateWithoutAssets() {
        #expect(Diagnostics.run(input(netWorth: 0, investable: 0, illiquid: 0))
                .diagnosis(.realEstateShare)?.status == .unknown)
    }

    // MARK: - 3) 국가 배분

    @Test("목표 ±허용오차 안이면 지킴, 두 배까지는 주의")
    func countryMixThresholds() {
        // 목표 미국 60%, 허용 ±5%p. 투자자산 7억 기준.
        #expect(Diagnostics.run(input(us: 420_000_000, kr: 280_000_000))   // 60.0%
                .diagnosis(.countryMix)?.status == .pass)
        #expect(Diagnostics.run(input(us: 469_000_000, kr: 231_000_000))   // 67.0% → +7%p
                .diagnosis(.countryMix)?.status == .watch)
        #expect(Diagnostics.run(input(us: 560_000_000, kr: 140_000_000))   // 80.0% → +20%p
                .diagnosis(.countryMix)?.status == .act)
        #expect(Diagnostics.run(input(us: 140_000_000, kr: 560_000_000))   // 20.0% → −40%p
                .diagnosis(.countryMix)?.status == .act)
    }

    @Test("목표를 바꾸면 판정도 따라 바뀐다 — 사용자가 정하는 값이다")
    func countryMixIsConfigurable() {
        let holdings = (us: 560_000_000, kr: 140_000_000)   // 미국 80%
        #expect(Diagnostics.run(input(us: holdings.us, kr: holdings.kr, usTargetBP: 6_000))
                .diagnosis(.countryMix)?.status == .act)
        #expect(Diagnostics.run(input(us: holdings.us, kr: holdings.kr, usTargetBP: 8_000))
                .diagnosis(.countryMix)?.status == .pass)
    }

    // MARK: - 4) 세제혜택 계좌

    private func account(_ kind: AccountKind, paid: Int, limit: Int) -> LimitAccountInput {
        LimitAccountInput(kind: kind, name: kind.label,
                          contributedThisYear: won(paid), annualLimit: won(limit))
    }

    @Test("한도를 다 채우면 지킴")
    func limitsFilled() {
        let result = Diagnostics.run(input(accounts: [
            account(.irp, paid: 3_000_000, limit: 3_000_000),
            account(.pensionSavings, paid: 6_000_000, limit: 6_000_000)
        ]))
        #expect(result.diagnosis(.taxAdvantagedOrder)?.status == .pass)
        #expect(result.diagnosis(.taxAdvantagedOrder)?.progress == 1)
    }

    @Test("한도를 안 넣으면 판단하지 않는다 — 앱이 세법을 따라가지 않는다")
    func limitsUnknown() {
        #expect(Diagnostics.run(input()).diagnosis(.taxAdvantagedOrder)?.status == .unknown)
        // 한도가 0인 계좌만 있어도 마찬가지다.
        #expect(Diagnostics.run(input(accounts: [account(.isa, paid: 0, limit: 0)]))
                .diagnosis(.taxAdvantagedOrder)?.status == .unknown)
    }

    @Test("남은 한도가 있으면 우선순위가 앞선 계좌부터 지목한다")
    func limitsPointToFirstUnfilled() throws {
        // 사용자가 정한 순서는 IRP → 연금저축 → ISA.
        // 입력 순서를 뒤집어 넣어도 IRP 를 먼저 지목해야 한다.
        let result = Diagnostics.run(input(accounts: [
            account(.isa, paid: 0, limit: 20_000_000),
            account(.pensionSavings, paid: 0, limit: 6_000_000),
            account(.irp, paid: 1_000_000, limit: 3_000_000)
        ]))
        let diagnosis = try #require(result.diagnosis(.taxAdvantagedOrder))
        #expect(diagnosis.action.contains("IRP"))
        #expect(diagnosis.status != .pass)
    }

    @Test("채운 비율은 한도를 넘겨 넣어도 100%를 넘지 않는다")
    func limitsOverpaidIsCapped() {
        // 한도 초과분까지 세면 "120% 채움" 같은 문장이 나온다.
        let result = Diagnostics.run(input(accounts: [
            account(.irp, paid: 5_000_000, limit: 3_000_000)
        ]))
        #expect(result.diagnosis(.taxAdvantagedOrder)?.progress == 1)
        #expect(result.diagnosis(.taxAdvantagedOrder)?.status == .pass)
    }

    // MARK: - 5) 72의 법칙

    @Test("72를 수익률로 나눈다")
    func doubling() {
        let eight = Diagnostics.run(input(returnBP: 800)).diagnosis(.doublingTime)
        #expect(eight?.headline.contains("9년마다") == true)

        // 72÷7 = 10.285… → 소수 첫째 자리에서 10.3
        let seven = Diagnostics.run(input(returnBP: 700)).diagnosis(.doublingTime)
        #expect(seven?.headline.contains("10.3년마다") == true)
    }

    @Test("적립까지 세면 훨씬 빠르다는 것을 함께 말한다")
    func doublingWithContribution() {
        // 72의 법칙은 적립을 세지 않는다. 두 숫자를 나란히 두지 않으면
        // "9년이나 걸린다"는 잘못된 인상만 남는다.
        let alone = Diagnostics.run(input(returnBP: 800)).diagnosis(.doublingTime)
        #expect(alone?.headline.contains("적립까지") == false)

        let withPlan = Diagnostics.run(input(returnBP: 800, doublingYear: 2032))
            .diagnosis(.doublingTime)
        #expect(withPlan?.headline.contains("적립까지 세면 6년") == true)
    }

    @Test("좋고 나쁨을 판정하지 않는다 — 눈금이다")
    func doublingIsNotAJudgement() {
        #expect(Diagnostics.run(input(returnBP: 300)).diagnosis(.doublingTime)?.status == .pass)
        #expect(Diagnostics.run(input(returnBP: 1_200)).diagnosis(.doublingTime)?.status == .pass)
        #expect(Diagnostics.run(input(returnBP: 0)).diagnosis(.doublingTime)?.status == .unknown)
    }

    // MARK: - 6) 선저축

    @Test("저축률은 기준의 80%를 경계로 주의와 조치를 가른다")
    func savings() {
        // 기준 10%. 월 소득 800만이면 80만이 기준선, 64만이 80% 선.
        #expect(Diagnostics.run(input(monthlyContribution: 800_000))
                .diagnosis(.savingsRate)?.status == .pass)
        #expect(Diagnostics.run(input(monthlyContribution: 700_000))
                .diagnosis(.savingsRate)?.status == .watch)
        #expect(Diagnostics.run(input(monthlyContribution: 400_000))
                .diagnosis(.savingsRate)?.status == .act)
    }

    @Test("소득을 안 넣으면 저축률을 판단하지 않는다")
    func savingsWithoutIncome() {
        #expect(Diagnostics.run(input(monthlyIncome: 0)).diagnosis(.savingsRate)?.status == .unknown)
    }

    // MARK: - 목록

    @Test("여섯 가지를 모두 돌려주고, 할 일이 위로 온다")
    func ordering() {
        let result = Diagnostics.run(input(
            illiquid: 400_000_000,              // act
            monthlyContribution: 400_000,       // act
            projected: 1_500_000_000            // pass
        ))
        #expect(result.diagnoses.count == DiagnosisKind.allCases.count)

        let statuses = result.sorted.map(\.status)
        #expect(statuses.first == .act)
        // 정렬은 안정적이어야 한다 — 같은 상태끼리는 규칙 순서를 지킨다.
        #expect(statuses == statuses.sorted { $0.priority < $1.priority })
    }

    @Test("모든 진단은 제목 · 결론 · 할 일 · 이유를 갖는다")
    func everyDiagnosisIsComplete() {
        for diagnosis in Diagnostics.run(input(projected: 1_500_000_000)).diagnoses {
            #expect(!diagnosis.title.isEmpty)
            #expect(!diagnosis.headline.isEmpty)
            #expect(!diagnosis.action.isEmpty)
            #expect(!diagnosis.rationale.isEmpty)
        }
    }
}
