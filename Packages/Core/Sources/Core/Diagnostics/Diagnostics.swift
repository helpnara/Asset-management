import Foundation

/// 자산 진단 — 상시 점검.
///
/// **가장 큰 원칙: 최종 투자 목적은 노후준비다.**
/// 그래서 모든 규칙은 "이게 은퇴 시점의 나에게 무슨 뜻인가"로 환원된다.
/// 수익률을 올리는 규칙이 아니라 **노후 준비를 망치지 않는** 규칙들이다.
///
/// 규칙은 막지 않고 알리기만 한다. 예외는 항상 있고 사용자가 자기 돈의 주인이다
/// (설계 2.7). 그래서 상태가 `위반`이 아니라 `조치`다 — 무엇을 하면 되는지까지 말한다.
public enum DiagnosisStatus: String, Sendable, Hashable, CaseIterable {
    /// 기준을 지키고 있다.
    case pass
    /// 아직 괜찮지만 경계에 가까워졌다.
    case watch
    /// 기준을 벗어났다. 할 일이 있다.
    case act
    /// 판단에 필요한 값이 아직 없다. **모르면 모른다고 한다.**
    case unknown

    public var label: String {
        switch self {
        case .pass: return "지킴"
        case .watch: return "주의"
        case .act: return "조치"
        case .unknown: return "입력 필요"
        }
    }

    /// 목록에서 위로 올릴 순서. 할 일이 먼저 보여야 한다.
    public var priority: Int {
        switch self {
        case .act: return 0
        case .watch: return 1
        case .unknown: return 2
        case .pass: return 3
        }
    }
}

public enum DiagnosisKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case retirementTarget    // 1) 4% 규칙 — 연 생활비의 25배
    case realEstateShare     // 2) 부동산 비중 상한
    case countryMix          // 3) 미국·한국 주식 비율
    case taxAdvantagedOrder  // 4) 세제혜택 계좌 채우는 순서
    case doublingTime        // 5) 72의 법칙
    case savingsRate         // 6) 선저축 비율

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .retirementTarget: return "은퇴 필요 자금"
        case .realEstateShare: return "부동산 비중"
        case .countryMix: return "국가 배분"
        case .taxAdvantagedOrder: return "세제혜택 계좌"
        case .doublingTime: return "자산이 두 배 되는 시점"
        case .savingsRate: return "선저축 비율"
        }
    }

    /// 왜 이 기준인가. 숫자가 아니라 이유를 기억해야 규칙이 산다.
    public var rationale: String {
        switch self {
        case .retirementTarget:
            return "연 생활비의 25배가 있으면 매년 4%씩 꺼내 써도 원금이 잘 버팁니다. 은퇴 준비의 결승선을 하나의 숫자로 만든 것입니다."
        case .realEstateShare:
            return "부동산은 팔지 않으면 생활비로 쓸 수 없습니다. 비중이 크면 자산은 많은데 쓸 돈이 없는 노후가 됩니다."
        case .countryMix:
            return "한 나라에 몰리면 그 나라의 20년이 곧 내 노후가 됩니다. 목표 비중을 정해 두고 그 근처에서 유지합니다."
        case .taxAdvantagedOrder:
            return "같은 돈을 넣어도 세액공제만큼 수익률이 먼저 붙습니다. 한도는 해가 바뀌면 사라지고 되돌릴 수 없습니다."
        case .doublingTime:
            return "복리가 얼마나 느리고 확실한지 보는 눈금입니다. 이 숫자가 은퇴까지 몇 번 도는지가 실제 준비의 크기입니다."
        case .savingsRate:
            return "쓰고 남은 돈을 모으면 남지 않습니다. 노후 준비는 수익률보다 저축률이 먼저 결정합니다."
        }
    }
}

public struct Diagnosis: Sendable, Hashable, Identifiable {
    public let kind: DiagnosisKind
    public let status: DiagnosisStatus
    /// 한 줄 결론. 반드시 숫자를 포함한다.
    public let headline: String
    /// 지금 무엇을 하면 되는가.
    public let action: String
    /// 게이지에 그릴 현재 위치 (0...1로 자름). nil이면 게이지를 그리지 않는다.
    public let progress: Double?

    public var id: String { kind.rawValue }
    public var title: String { kind.title }
    public var rationale: String { kind.rationale }
}

/// 연간 납입 한도가 있는 계좌 하나.
public struct LimitAccountInput: Sendable, Hashable {
    public var kind: AccountKind
    public var name: String
    /// 올해 넣은 금액. 사용자가 직접 적는다 (ADR-0005 — 가져오지 않는다).
    public var contributedThisYear: Money
    /// 연간 한도. 0이면 판단하지 않는다.
    public var annualLimit: Money

    public init(kind: AccountKind, name: String, contributedThisYear: Money, annualLimit: Money) {
        self.kind = kind
        self.name = name
        self.contributedThisYear = contributedThisYear
        self.annualLimit = annualLimit
    }

    public var remaining: Money {
        let left = annualLimit.minorUnits - contributedThisYear.minorUnits
        return Money(minorUnits: max(left, 0), currency: annualLimit.currency)
    }

    public var isFull: Bool { annualLimit.minorUnits > 0 && remaining.isZero }
}

public struct DiagnosticsInput: Sendable {
    // MARK: 지금 자산
    public var netWorth: Money
    public var investable: Money
    /// 부동산 + 전세보증금. 팔지 않으면 생활비로 못 쓰는 자산.
    public var illiquid: Money
    /// 투자자산의 국가별 분해.
    public var byCountry: [String: Money]

    // MARK: 계획
    /// 은퇴 후 한 달 생활비. 0이면 은퇴 필요 자금을 판단하지 않는다.
    public var monthlySpending: Money
    /// 인출률. 4% 규칙이면 400bp.
    public var withdrawalRate: Ratio
    /// 세후 월 소득. 0이면 저축률을 판단하지 않는다.
    public var monthlyIncome: Money
    public var monthlyContribution: Money
    /// 최소 저축률. 10%면 1000bp.
    public var savingsFloor: Ratio
    public var annualReturn: Ratio
    /// 부동산 비중 상한. 35%면 3500bp.
    public var illiquidCap: Ratio
    /// 미국 목표 비중. 나머지가 한국 몫이라고 보지 않는다 — 그 외 국가도 있다.
    public var usTarget: Ratio
    /// 목표에서 이만큼 벗어나도 조치로 보지 않는다. 5%p면 500bp.
    public var mixTolerance: Ratio

    // MARK: 시점
    public var yearsToRetirement: Int
    /// 결정론적 궤적이 말하는 은퇴 시점 예상 자산. nil이면 비교를 생략한다.
    public var projectedAtRetirement: Money?
    /// 적립까지 감안한 실제 배가 연도. `Projection` 의 마일스톤에서 가져온다.
    public var doublingYear: Int?
    public var currentYear: Int

    // MARK: 계좌
    public var limitAccounts: [LimitAccountInput]

    public init(
        netWorth: Money,
        investable: Money,
        illiquid: Money,
        byCountry: [String: Money],
        monthlySpending: Money,
        withdrawalRate: Ratio,
        monthlyIncome: Money,
        monthlyContribution: Money,
        savingsFloor: Ratio,
        annualReturn: Ratio,
        illiquidCap: Ratio,
        usTarget: Ratio,
        mixTolerance: Ratio,
        yearsToRetirement: Int,
        projectedAtRetirement: Money? = nil,
        doublingYear: Int? = nil,
        currentYear: Int,
        limitAccounts: [LimitAccountInput] = []
    ) {
        self.netWorth = netWorth
        self.investable = investable
        self.illiquid = illiquid
        self.byCountry = byCountry
        self.monthlySpending = monthlySpending
        self.withdrawalRate = withdrawalRate
        self.monthlyIncome = monthlyIncome
        self.monthlyContribution = monthlyContribution
        self.savingsFloor = savingsFloor
        self.annualReturn = annualReturn
        self.illiquidCap = illiquidCap
        self.usTarget = usTarget
        self.mixTolerance = mixTolerance
        self.yearsToRetirement = yearsToRetirement
        self.projectedAtRetirement = projectedAtRetirement
        self.doublingYear = doublingYear
        self.currentYear = currentYear
        self.limitAccounts = limitAccounts
    }
}

public struct DiagnosticsResult: Sendable, Hashable {
    public let diagnoses: [Diagnosis]

    public func diagnosis(_ kind: DiagnosisKind) -> Diagnosis? {
        diagnoses.first { $0.kind == kind }
    }

    public func count(_ status: DiagnosisStatus) -> Int {
        diagnoses.filter { $0.status == status }.count
    }

    /// 할 일이 먼저 오도록 정렬한 목록.
    public var sorted: [Diagnosis] {
        diagnoses.sorted {
            $0.status.priority != $1.status.priority
                ? $0.status.priority < $1.status.priority
                : DiagnosisKind.allCases.firstIndex(of: $0.kind)!
                    < DiagnosisKind.allCases.firstIndex(of: $1.kind)!
        }
    }
}

public enum Diagnostics {

    public static func run(_ input: DiagnosticsInput) -> DiagnosticsResult {
        DiagnosticsResult(diagnoses: [
            retirementTarget(input),
            realEstateShare(input),
            countryMix(input),
            taxAdvantagedOrder(input),
            doublingTime(input),
            savingsRate(input)
        ])
    }

    /// 은퇴 시점에 필요한 자산. 연 생활비 ÷ 인출률.
    /// 4%면 25배, 3.5%면 약 28.6배가 된다 — 25를 상수로 박지 않는 이유다.
    public static func requiredNestEgg(monthlySpending: Money, withdrawalRate: Ratio) -> Money? {
        guard !monthlySpending.isZero, withdrawalRate.basisPoints > 0 else { return nil }
        let annual = Decimal(monthlySpending.minorUnits) * 12
        return Money(
            minorUnits: Decimals.roundedInt(annual / withdrawalRate.fraction, rounding: .bankers),
            currency: monthlySpending.currency
        )
    }

    // MARK: - 1) 4% 규칙

    private static func retirementTarget(_ input: DiagnosticsInput) -> Diagnosis {
        guard let required = requiredNestEgg(monthlySpending: input.monthlySpending,
                                             withdrawalRate: input.withdrawalRate) else {
            return Diagnosis(
                kind: .retirementTarget,
                status: .unknown,
                headline: "은퇴 후 월 생활비를 정해야 계산할 수 있습니다",
                action: "진단 기준에서 은퇴 후 월 생활비를 넣으세요. 지금 쓰는 생활비에서 출퇴근·교육비를 빼고 의료비를 더하면 대략 맞습니다.",
                progress: nil
            )
        }

        let multiple = PercentFormatter.oneDecimal(input.withdrawalRate.fraction)
        let requiredText = KoreanAmountFormatter.abbreviated(required, suffix: "원")

        // 판단은 **은퇴 시점 예상**으로 한다. 지금 부족한 건 당연하다 —
        // 아직 은퇴하지 않았으니까. 지금 잔고로 겁을 주면 규칙이 무의미해진다.
        guard let projected = input.projectedAtRetirement else {
            let share = ratio(input.netWorth, of: required)
            return Diagnosis(
                kind: .retirementTarget,
                status: .unknown,
                headline: "필요 \(requiredText) · 지금 \(percent(share))",
                action: "계획 탭에서 월 적립액과 기대수익률을 넣으면 은퇴 시점 예상과 비교합니다.",
                progress: share
            )
        }

        let share = ratio(projected, of: required)
        let projectedText = KoreanAmountFormatter.abbreviated(projected, suffix: "원")
        let gap = Money(minorUnits: required.minorUnits - projected.minorUnits,
                        currency: required.currency)

        let status: DiagnosisStatus
        let action: String
        if projected >= required {
            status = .pass
            let surplus = Money(minorUnits: projected.minorUnits - required.minorUnits,
                                currency: required.currency)
            action = "은퇴 시점 예상이 필요액을 \(KoreanAmountFormatter.abbreviated(surplus, suffix: "원")) 넘습니다. 지금 속도를 유지하세요."
        } else if share >= 0.9 {
            status = .watch
            action = "\(KoreanAmountFormatter.abbreviated(gap, suffix: "원")) 모자랍니다. 시뮬레이션 탭에서 월 적립을 조금 올려 보면 언제 닿는지 보입니다."
        } else {
            status = .act
            action = "\(KoreanAmountFormatter.abbreviated(gap, suffix: "원")) 모자랍니다. 적립액을 올리거나, 은퇴 후 생활비를 낮추거나, 은퇴 시점을 늦추는 세 가지 중 하나가 필요합니다."
        }

        return Diagnosis(
            kind: .retirementTarget,
            status: status,
            headline: "필요 \(requiredText) (연 생활비의 \(multipleText(input.withdrawalRate))배) · 은퇴 시점 예상 \(projectedText)",
            action: action + " 인출률 \(multiple)% 기준입니다.",
            progress: share
        )
    }

    /// 인출률의 역수 = 연 생활비의 몇 배. 4% → 25배.
    private static func multipleText(_ rate: Ratio) -> String {
        let multiple = Decimal(1) / rate.fraction
        let rounded = Decimals.roundedInt(multiple * 10, rounding: .plain)
        return rounded % 10 == 0 ? "\(rounded / 10)" : "\(rounded / 10).\(rounded % 10)"
    }

    // MARK: - 2) 부동산 비중

    private static func realEstateShare(_ input: DiagnosticsInput) -> Diagnosis {
        guard input.netWorth.minorUnits > 0 else {
            return Diagnosis(kind: .realEstateShare, status: .unknown,
                             headline: "자산을 먼저 등록하세요",
                             action: "자산 탭에서 구성원 · 계좌 · 종목을 넣으면 비중이 계산됩니다.",
                             progress: nil)
        }

        let share = ratio(input.illiquid, of: input.netWorth)
        let cap = decimalToDouble(input.illiquidCap.fraction)
        let capText = PercentFormatter.oneDecimal(input.illiquidCap.fraction)

        let status: DiagnosisStatus
        let action: String
        if share <= cap {
            // 상한의 90%를 넘으면 미리 알린다. 부동산은 하루아침에 못 줄인다.
            status = share >= cap * 0.9 ? .watch : .pass
            action = status == .watch
                ? "상한 \(capText)%에 가깝습니다. 앞으로의 적립은 금융자산 쪽으로 두세요."
                : "상한 \(capText)% 안입니다. 새로 부동산을 늘릴 때만 다시 보면 됩니다."
        } else {
            status = .act
            let excess = Money(
                minorUnits: input.illiquid.minorUnits
                    - Decimals.roundedInt(Decimal(input.netWorth.minorUnits) * input.illiquidCap.fraction,
                                          rounding: .bankers),
                currency: input.netWorth.currency
            )
            action = "상한을 \(KoreanAmountFormatter.abbreviated(excess, suffix: "원")) 넘습니다. 당장 팔라는 뜻은 아닙니다 — 금융자산이 자라면 비중은 저절로 내려갑니다. 부동산을 더 늘리지 않는 것만으로 충분할 때가 많습니다."
        }

        return Diagnosis(
            kind: .realEstateShare,
            status: status,
            headline: "부동산 · 전세보증금 \(percent(share)) (상한 \(capText)%)",
            action: action,
            progress: cap > 0 ? min(share / cap, 1.5) : nil
        )
    }

    // MARK: - 3) 국가 배분

    private static func countryMix(_ input: DiagnosticsInput) -> Diagnosis {
        guard input.investable.minorUnits > 0 else {
            return Diagnosis(kind: .countryMix, status: .unknown,
                             headline: "투자자산을 먼저 등록하세요",
                             action: "종목마다 상장 국가를 골라 두면 비중이 계산됩니다.",
                             progress: nil)
        }

        let us = ratio(input.byCountry["US"] ?? .zero(input.investable.currency), of: input.investable)
        let kr = ratio(input.byCountry["KR"] ?? .zero(input.investable.currency), of: input.investable)
        let target = decimalToDouble(input.usTarget.fraction)
        let tolerance = decimalToDouble(input.mixTolerance.fraction)
        let drift = us - target

        let status: DiagnosisStatus
        let action: String
        if abs(drift) <= tolerance {
            status = .pass
            action = "목표 \(PercentFormatter.oneDecimal(input.usTarget.fraction))% 근처입니다. 다음 적립을 적은 쪽에 넣으면 저절로 맞춰집니다."
        } else if abs(drift) <= tolerance * 2 {
            status = .watch
            action = drift > 0
                ? "미국이 목표보다 \(percent(drift)) 많습니다. 파는 대신 다음 적립을 한국 쪽에 넣어 맞추세요 — 팔면 세금이 붙습니다."
                : "미국이 목표보다 \(percent(-drift)) 적습니다. 다음 적립을 미국 쪽에 넣으세요."
        } else {
            status = .act
            action = drift > 0
                ? "미국이 목표보다 \(percent(drift)) 많습니다. 적립만으로 되돌리기 어려운 폭이면 일부 조정을 고려하되, 세금과 수수료를 먼저 계산해 보세요."
                : "미국이 목표보다 \(percent(-drift)) 적습니다. 적립 방향을 미국 쪽으로 돌리세요."
        }

        return Diagnosis(
            kind: .countryMix,
            status: status,
            headline: "미국 \(percent(us)) · 한국 \(percent(kr)) (목표 미국 \(PercentFormatter.oneDecimal(input.usTarget.fraction))% ±\(PercentFormatter.oneDecimal(input.mixTolerance.fraction))%p)",
            action: action,
            progress: us
        )
    }

    // MARK: - 4) 세제혜택 계좌 채우는 순서

    /// 채우는 순서. 우선순위가 앞선 계좌를 먼저 채운다.
    ///
    /// 이 순서는 사용자가 정한 것이다 (IRP → 연금저축 → ISA → 일반).
    /// 세법이 바뀌거나 생각이 바뀌면 여기가 아니라 설정에서 고칠 수 있어야 한다 —
    /// 아직은 상수다.
    public static let contributionOrder: [AccountKind] = [.irp, .pensionSavings, .isa]

    private static func taxAdvantagedOrder(_ input: DiagnosticsInput) -> Diagnosis {
        let tracked = input.limitAccounts
            .filter { $0.annualLimit.minorUnits > 0 }
            .sorted { lhs, rhs in
                let l = contributionOrder.firstIndex(of: lhs.kind) ?? contributionOrder.count
                let r = contributionOrder.firstIndex(of: rhs.kind) ?? contributionOrder.count
                return l < r
            }

        guard !tracked.isEmpty else {
            return Diagnosis(kind: .taxAdvantagedOrder, status: .unknown,
                             headline: "한도 계좌의 연간 한도를 아직 안 넣었습니다",
                             action: "자산 탭에서 IRP · 연금저축 · ISA 계좌를 열고 올해 납입액과 연간 한도를 적으세요. 세법이 바뀌면 한도도 직접 고칩니다 — 앱이 세법을 따라가지 않습니다.",
                             progress: nil)
        }

        let totalLimit = tracked.reduce(0) { $0 + $1.annualLimit.minorUnits }
        let totalPaid = tracked.reduce(0) { $0 + min($1.contributedThisYear.minorUnits, $1.annualLimit.minorUnits) }
        let filled = totalLimit > 0 ? Double(totalPaid) / Double(totalLimit) : 0

        let next = tracked.first { !$0.isFull }
        let remaining = Money(minorUnits: totalLimit - totalPaid,
                              currency: input.netWorth.currency)

        guard let next else {
            return Diagnosis(
                kind: .taxAdvantagedOrder,
                status: .pass,
                headline: "올해 한도를 모두 채웠습니다",
                action: "여기서부터는 일반 계좌 차례입니다. 내년 1월에 한도가 새로 열립니다.",
                progress: 1
            )
        }

        // 남은 달이 적을수록 급하다. 연말에 몰아 넣으려다 놓치는 것이 흔한 실패다.
        let monthsLeft = max(12 - monthOfYear + 1, 0)
        let status: DiagnosisStatus = monthsLeft <= 3 ? .act : .watch

        return Diagnosis(
            kind: .taxAdvantagedOrder,
            status: status,
            headline: "올해 한도 \(percent(filled)) 채움 · \(KoreanAmountFormatter.abbreviated(remaining, suffix: "원")) 남음",
            action: "다음 적립은 \(next.name.isEmpty ? next.kind.label : next.name)부터 채우세요 (\(KoreanAmountFormatter.abbreviated(next.remaining, suffix: "원")) 남음). 올해가 \(monthsLeft)달 남았고, 못 채운 한도는 해가 바뀌면 사라집니다.",
            progress: filled
        )
    }

    /// 남은 달 계산에만 쓴다. 입력에 월을 따로 받지 않는다.
    private static var monthOfYear: Int {
        Calendar.current.component(.month, from: .now)
    }

    // MARK: - 5) 72의 법칙

    private static func doublingTime(_ input: DiagnosticsInput) -> Diagnosis {
        let percentReturn = decimalToDouble(input.annualReturn.percent)
        guard percentReturn > 0 else {
            return Diagnosis(kind: .doublingTime, status: .unknown,
                             headline: "기대수익률이 0입니다",
                             action: "계획 탭에서 연 기대수익률을 넣으세요.",
                             progress: nil)
        }

        let years = 72 / percentReturn
        let rounded = (years * 10).rounded() / 10

        // 72의 법칙은 **적립을 세지 않는다**. 매달 넣는 돈이 있으면 실제로는
        // 훨씬 빨리 두 배가 된다. 두 숫자를 나란히 두지 않으면 규칙이 거짓말이 된다.
        var headline = "연 \(PercentFormatter.oneDecimal(input.annualReturn.fraction))%면 \(format(rounded))년마다 두 배"
        var action = "72를 수익률로 나눈 값입니다. 적립을 세지 않은, 굴리기만 할 때의 속도입니다."

        if let doublingYear = input.doublingYear {
            let actual = doublingYear - input.currentYear
            headline += " · 적립까지 세면 \(actual)년"
            action = "72÷\(PercentFormatter.oneDecimal(input.annualReturn.fraction))=\(format(rounded))년은 굴리기만 할 때입니다. 매달 넣는 돈까지 세면 \(doublingYear)년에 두 배가 됩니다. 이 차이가 적립의 값입니다."
        }

        let turns = years > 0 ? Double(input.yearsToRetirement) / years : 0
        if input.yearsToRetirement > 0 {
            action += " 은퇴까지 \(input.yearsToRetirement)년이면 이 바퀴를 \(format((turns * 10).rounded() / 10))번 돕니다."
        }

        return Diagnosis(
            kind: .doublingTime,
            status: .pass,   // 좋고 나쁨을 판정하는 규칙이 아니다. 눈금이다.
            headline: headline,
            action: action,
            progress: nil
        )
    }

    // MARK: - 6) 선저축 비율

    private static func savingsRate(_ input: DiagnosticsInput) -> Diagnosis {
        guard input.monthlyIncome.minorUnits > 0 else {
            return Diagnosis(kind: .savingsRate, status: .unknown,
                             headline: "세후 월 소득을 넣어야 계산할 수 있습니다",
                             action: "진단 기준에서 세후 월 소득을 넣으세요. 이 값은 저축률 계산에만 쓰고 다른 화면에는 나오지 않습니다.",
                             progress: nil)
        }

        let rate = ratio(input.monthlyContribution, of: input.monthlyIncome)
        let floor = decimalToDouble(input.savingsFloor.fraction)
        let floorText = PercentFormatter.oneDecimal(input.savingsFloor.fraction)

        let status: DiagnosisStatus
        let action: String
        if rate >= floor {
            status = .pass
            action = "기준 \(floorText)%를 넘습니다. 월급이 오르면 오른 만큼 적립도 올리면 비율이 유지됩니다."
        } else if rate >= floor * 0.8 {
            status = .watch
            let need = neededContribution(input)
            action = "기준까지 월 \(KoreanAmountFormatter.abbreviated(need, suffix: "원")) 남았습니다. 월급날 자동이체를 먼저 걸어 두는 것이 가장 확실합니다."
        } else {
            status = .act
            let need = neededContribution(input)
            action = "기준까지 월 \(KoreanAmountFormatter.abbreviated(need, suffix: "원")) 모자랍니다. 쓰고 남은 돈을 모으면 남지 않습니다 — 월급날 먼저 빠져나가게 두세요."
        }

        return Diagnosis(
            kind: .savingsRate,
            status: status,
            headline: "월 소득의 \(percent(rate)) 저축 (기준 \(floorText)% 이상)",
            action: action,
            progress: floor > 0 ? min(rate / floor, 1.5) : nil
        )
    }

    private static func neededContribution(_ input: DiagnosticsInput) -> Money {
        let target = Decimals.roundedInt(Decimal(input.monthlyIncome.minorUnits) * input.savingsFloor.fraction,
                                         rounding: .bankers)
        return Money(minorUnits: max(target - input.monthlyContribution.minorUnits, 0),
                     currency: input.monthlyIncome.currency)
    }

    // MARK: - 보조

    private static func ratio(_ value: Money, of base: Money) -> Double {
        guard base.minorUnits != 0 else { return 0 }
        return Double(value.minorUnits) / Double(base.minorUnits)
    }

    private static func percent(_ value: Double) -> String {
        PercentFormatter.oneDecimal(Decimals.fromDouble(value)) + "%"
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : "\(value)"
    }
}
