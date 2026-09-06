import Foundation

/// 결정론적 프로젝션의 입력.
///
/// 몬테카를로(신뢰구간 밴드)는 이 위에 얹는다. 먼저 중앙값 한 줄을 정확히 그린다.
/// 특정 시점의 큰 자금 이동. 전세보증금 전환, 퇴직금 유입, 주택 구입 같은 것들.
///
/// 23년 복리에서 목돈 하나가 결과를 크게 바꾼다 — 1억이 9년 굴러 2억이 된다.
/// 이걸 빼놓고 그린 궤적은 궤적이 아니다.
public struct CashEventInput: Sendable, Hashable {
    public var date: Date
    /// 부호로 방향을 표현한다. 양수는 유입, 음수는 유출.
    public var amount: Money
    public var label: String

    public init(date: Date, amount: Money, label: String = "") {
        self.date = date
        self.amount = amount
        self.label = label
    }
}

/// 은퇴 후 들어오는 소득. 국민연금 · 퇴직연금 · 개인연금 · 임대소득.
///
/// **금액은 오늘 돈 기준으로 적는다.** "65세부터 월 150만원"이라고 할 때
/// 그 150만원은 지금 물가로 말한 것이지, 20년 뒤의 액면가가 아니다.
/// 물가연동 여부를 따로 두는 이유는 국민연금은 연동되고 확정 개인연금은
/// 안 되기 때문이다 — 이 차이가 30년이면 결과를 절반으로 가른다.
public struct IncomeStreamInput: Sendable, Hashable {
    public var label: String
    /// 오늘 돈 기준 월 수령액.
    public var monthlyAmount: Money
    public var startYear: Int
    /// nil 이면 종신.
    public var endYear: Int?
    /// 물가에 연동되는가. 국민연금은 true, 확정형 개인연금은 false.
    public var isInflationLinked: Bool

    public init(
        label: String = "",
        monthlyAmount: Money,
        startYear: Int,
        endYear: Int? = nil,
        isInflationLinked: Bool = true
    ) {
        self.label = label
        self.monthlyAmount = monthlyAmount
        self.startYear = startYear
        self.endYear = endYear
        self.isInflationLinked = isInflationLinked
    }

    func isActive(inYear year: Int) -> Bool {
        year >= startYear && (endYear.map { year <= $0 } ?? true)
    }
}

/// 프로필이 같은 돈 한 덩어리.
///
/// 순자산을 통째로 한 수익률에 굴리면 전세보증금까지 복리로 불어난다
/// (docs/08-feedback.md 11번). 그래서 덩어리로 나눠 각자의 속도로 굴린다.
public struct BalanceBucket: Sendable, Hashable {
    public var profile: ReturnProfile
    public var amount: Money
    public var annualReturn: Ratio

    public init(profile: ReturnProfile, amount: Money, annualReturn: Ratio) {
        self.profile = profile
        self.amount = amount
        self.annualReturn = annualReturn
    }
}

public struct ProjectionInput: Sendable, Hashable {
    public var startDate: Date
    public var endDate: Date
    /// 프로필별로 나뉜 시작 잔고. 적립과 목돈은 투자자산 덩어리로 들어가고,
    /// 은퇴 후 인출은 투자자산부터 꺼낸다.
    public var buckets: [BalanceBucket]
    public var monthlyContribution: Money
    public var annualReturn: Ratio
    /// 적립액의 연 증가율 (연봉 상승률).
    public var annualContributionGrowth: Ratio
    public var inflation: Ratio
    public var cashEvents: [CashEventInput]
    /// 마일스톤 판정에 쓴다. nil이면 목표 도달을 찾지 않는다.
    public var targetAmount: Money?
    /// 오늘 돈 기준 연 소득. `수익 > 연봉` 마일스톤에만 쓴다.
    /// 0이면 그 마일스톤을 찾지 않는다.
    public var annualIncome: Money

    /// 은퇴 시점. 이 날짜까지는 적립하고, 이후로는 인출한다.
    ///
    /// `endDate` 와 같으면(기본값) 은퇴 이후를 그리지 않는다 — 예전 동작 그대로다.
    /// `endDate` 를 더 뒤로 두면 그 사이가 인출 구간이 된다.
    public var retirementDate: Date
    /// 은퇴 후 월 생활비. **오늘 돈 기준**으로 적는다. 0이면 인출하지 않는다.
    public var monthlyRetirementSpending: Money
    /// 은퇴 후 소득. 생활비에서 이만큼을 뺀 나머지를 자산에서 꺼낸다.
    public var incomes: [IncomeStreamInput]

    /// 모든 덩어리의 합. 화면이 읽는 "지금 얼마" 는 여전히 이 값이다.
    public var startingBalance: Money {
        guard let first = buckets.first else { return .zero(.krw) }
        return buckets.dropFirst().reduce(first.amount) { $0 + $1.amount }
    }

    /// 덩어리를 나누지 않는 경우. **전액을 투자자산으로 본다** — 예전 동작 그대로다.
    public init(
        startDate: Date,
        endDate: Date,
        startingBalance: Money,
        monthlyContribution: Money,
        annualReturn: Ratio,
        annualContributionGrowth: Ratio = .zero,
        inflation: Ratio = .zero,
        cashEvents: [CashEventInput] = [],
        targetAmount: Money? = nil,
        annualIncome: Money? = nil,
        retirementDate: Date? = nil,
        monthlyRetirementSpending: Money? = nil,
        incomes: [IncomeStreamInput] = []
    ) {
        self.init(
            startDate: startDate,
            endDate: endDate,
            buckets: [BalanceBucket(profile: .investment,
                                    amount: startingBalance,
                                    annualReturn: annualReturn)],
            monthlyContribution: monthlyContribution,
            annualReturn: annualReturn,
            annualContributionGrowth: annualContributionGrowth,
            inflation: inflation,
            cashEvents: cashEvents,
            targetAmount: targetAmount,
            annualIncome: annualIncome,
            retirementDate: retirementDate,
            monthlyRetirementSpending: monthlyRetirementSpending,
            incomes: incomes
        )
    }

    public init(
        startDate: Date,
        endDate: Date,
        buckets: [BalanceBucket],
        monthlyContribution: Money,
        annualReturn: Ratio,
        annualContributionGrowth: Ratio = .zero,
        inflation: Ratio = .zero,
        cashEvents: [CashEventInput] = [],
        targetAmount: Money? = nil,
        annualIncome: Money? = nil,
        retirementDate: Date? = nil,
        monthlyRetirementSpending: Money? = nil,
        incomes: [IncomeStreamInput] = []
    ) {
        // **적립과 목돈이 들어갈 자리는 투자자산이다.** 하나도 없으면(전세보증금만
        // 있는 초기 상태 등) 빈 덩어리를 만들어 둔다. 이게 없으면 적립이 고정
        // 덩어리로 들어가 0% 로 굴러간다.
        var resolved = buckets
        if !resolved.contains(where: { $0.profile == .investment }) {
            let currency = resolved.first?.amount.currency ?? .krw
            resolved.insert(BalanceBucket(profile: .investment,
                                          amount: .zero(currency),
                                          annualReturn: annualReturn), at: 0)
        }
        let currency = resolved[0].amount.currency
        self.retirementDate = retirementDate ?? endDate
        self.monthlyRetirementSpending = monthlyRetirementSpending ?? .zero(currency)
        self.incomes = incomes
        self.startDate = startDate
        self.endDate = endDate
        self.buckets = resolved
        self.monthlyContribution = monthlyContribution
        self.annualReturn = annualReturn
        self.annualContributionGrowth = annualContributionGrowth
        self.inflation = inflation
        self.cashEvents = cashEvents
        self.targetAmount = targetAmount
        self.annualIncome = annualIncome ?? .zero(currency)
    }
}

/// 한 해의 결산. 로드맵 타임라인과 마일스톤 판정이 이걸 읽는다.
public struct YearSummary: Sendable, Hashable {
    public let year: Int
    public let endBalance: Money
    public let contributed: Money
    public let cashEvents: Money
    /// 은퇴 후 그 해에 자산에서 꺼낸 금액. 적립 구간에는 0이다.
    public let withdrawn: Money
    /// 그 해 수익 = 연말 − 연초 − 적립 − 목돈 + 인출.
    ///
    /// 인출을 빼놓고 계산하면 은퇴 이후의 "수익"이 통째로 음수가 되어
    /// 시장이 나빴던 것처럼 보인다. 실제로는 꺼내 쓴 것이다.
    public let gain: Money
}

/// 자동으로 판정되는 교차점.
///
/// 1페이지의 "수익 > 적립금", "일하지 않아도 되는 시점" 같은 라벨이 여기서 나온다.
/// 금액보다 이 라벨이 동기를 만든다.
public enum MilestoneKind: String, Sendable, Hashable, CaseIterable {
    /// 한 해 수익이 그 해 적립금을 넘어선 첫 해. 복리가 내 손을 앞지르는 순간이다.
    case returnsExceedContribution
    /// 시작 자산의 두 배.
    case doubled
    /// 한 해 수익이 연봉을 넘어선 첫 해. **돈이 나보다 많이 버는 순간**이다.
    case returnsExceedSalary
    /// 목표 금액 도달.
    case targetReached

    public var label: String {
        switch self {
        case .returnsExceedContribution: return "수익 > 적립금"
        case .doubled: return "자산 2배"
        case .returnsExceedSalary: return "수익 > 연봉"
        case .targetReached: return "목표 달성"
        }
    }

    public var detail: String {
        switch self {
        case .returnsExceedContribution: return "복리가 적립보다 많이 번다"
        case .doubled: return "시작 자산의 두 배"
        case .returnsExceedSalary: return "돈이 나보다 많이 번다"
        case .targetReached: return "은퇴 목표 금액에 닿는다"
        }
    }
}

public struct Milestone: Sendable, Hashable {
    public let kind: MilestoneKind
    public let year: Int
    public let balance: Money
}

public struct ProjectionPoint: Sendable, Hashable {
    public let date: Date
    /// 그때의 액면가.
    public let nominal: Money
    /// 오늘 돈으로 환산한 값. 30년 뒤 59억이 지금 얼마인지가 노후 준비의 진짜 질문이다.
    public let real: Money
}

public struct ProjectionResult: Sendable, Hashable {
    public let points: [ProjectionPoint]
    public let years: [YearSummary]
    public let milestones: [Milestone]
    /// 잔고가 0이 된 시점. nil 이면 기간 끝까지 버텼다.
    ///
    /// 이 앱에서 가장 무거운 숫자다. 그래서 **추정할 수 없으면 만들지 않는다** —
    /// 은퇴 후 생활비를 넣지 않으면 인출 자체를 하지 않으므로 언제나 nil 이다.
    public let depletion: Date?

    public var first: ProjectionPoint? { points.first }
    public var last: ProjectionPoint? { points.last }

    public func milestone(_ kind: MilestoneKind) -> Milestone? {
        milestones.first { $0.kind == kind }
    }

    /// 그 해에 속한 마지막 지점. 로드맵 타임라인이 연도별로 읽는다.
    public func point(inYear year: Int, calendar: Calendar = .current) -> ProjectionPoint? {
        points.last { calendar.component(.year, from: $0.date) == year }
    }
}

public enum Projection {

    /// 월 단위로 굴린다.
    ///
    /// 한 달의 순서는 **적립 → 수익**이다. 월초에 넣고 그 달 수익을 받는다는 뜻이다.
    /// 반대로 하면 첫 달 적립이 한 달을 놀게 되므로 이쪽이 실제에 가깝다.
    ///
    /// 은퇴 이후의 인출은 아직 다루지 않는다. 연금 소득 모델이 들어와야
    /// "생활비 − 연금"을 뺄 수 있고, 그전에 추정하면 틀린 숫자를 크게 보여주게 된다.
    /// 그래서 `endDate` 를 은퇴 시점으로 두고 거기서 멈춘다.
    public static func run(_ input: ProjectionInput, calendar: Calendar = .current) -> ProjectionResult {
        let base = input.startingBalance.currency
        let months = calendar.dateComponents([.month], from: input.startDate, to: input.endDate).month ?? 0
        guard months > 0 else {
            let single = ProjectionPoint(
                date: input.startDate,
                nominal: input.startingBalance,
                real: input.startingBalance
            )
            return ProjectionResult(points: [single], years: [], milestones: [], depletion: nil)
        }

        // 덩어리마다 자기 속도로 굴린다. 적립·목돈이 들어가고 인출이 먼저
        // 빠져나가는 곳은 투자자산이다.
        let growths = input.buckets.map { monthlyFactor(annual: $0.annualReturn) }
        let order = input.buckets.indices.sorted {
            input.buckets[$0].profile.drawdownOrder < input.buckets[$1].profile.drawdownOrder
        }
        let inflowIndex = input.buckets.firstIndex { $0.profile == .investment } ?? 0
        let inflation = monthlyFactor(annual: input.inflation)
        let contributionStep = Decimal(1) + input.annualContributionGrowth.fraction

        // 목돈은 그 달에 한 번 적용한다. 같은 달에 여러 건이면 합쳐서 넣는다.
        var eventsByMonth: [Int: Money] = [:]
        for event in input.cashEvents {
            let offset = calendar.dateComponents([.month], from: input.startDate, to: event.date).month ?? -1
            guard offset >= 1, offset <= months else { continue }
            eventsByMonth[offset, default: .zero(base)] += event.amount
        }

        var balances = input.buckets.map(\.amount)
        var balance = input.startingBalance
        var contribution = input.monthlyContribution
        var deflator = Decimal(1)
        var contributedByYear: [Int: Money] = [:]
        var eventsByYear: [Int: Money] = [:]
        var withdrawnByYear: [Int: Money] = [:]
        var depletion: Date?

        var points: [ProjectionPoint] = [
            ProjectionPoint(date: input.startDate, nominal: balance, real: balance)
        ]
        points.reserveCapacity(months + 1)

        for month in 1...months {
            let date = calendar.date(byAdding: .month, value: month, to: input.startDate) ?? input.startDate
            let year = calendar.component(.year, from: date)
            let event = eventsByMonth[month] ?? .zero(base)

            if !event.isZero { eventsByYear[year, default: .zero(base)] += event }
            deflator *= inflation

            if date <= input.retirementDate {
                // 적립 구간 — 월초에 넣고 그 달 수익을 받는다.
                contributedByYear[year, default: .zero(base)] += contribution
                balances[inflowIndex] += contribution + event
                if month % 12 == 0 {
                    contribution = contribution.scaled(by: contributionStep)
                }
            } else {
                // 인출 구간 — 생활비에서 연금 소득을 뺀 나머지를 자산에서 꺼낸다.
                //
                // 생활비와 연금은 **오늘 돈 기준**으로 적혀 있으므로 그 시점의
                // 물가(deflator)를 곱해 액면가로 올린다. 이걸 빼먹으면 30년 뒤에도
                // 지금 생활비로 살 수 있다는 거짓말이 된다.
                let withdrawal = monthlyWithdrawal(input, year: year, deflator: deflator, base: base)
                if !withdrawal.isZero { withdrawnByYear[year, default: .zero(base)] += withdrawal }

                balances[inflowIndex] += event

                // **투자자산부터 꺼낸다.** 전세보증금은 꺼내 쓸 수 있는 돈이
                // 아니므로 마지막이다. 전부 비면 그 달이 고갈 시점이다.
                var remaining = withdrawal
                for index in order where remaining.minorUnits > 0 {
                    let take = min(balances[index].minorUnits, remaining.minorUnits)
                    guard take > 0 else { continue }
                    balances[index] -= Money(minorUnits: take, currency: base)
                    remaining -= Money(minorUnits: take, currency: base)
                }
                if remaining.minorUnits > 0, depletion == nil { depletion = date }
            }

            for index in balances.indices {
                balances[index] = balances[index].scaled(by: growths[index])
            }
            balance = balances.dropFirst().reduce(balances[0], +)

            points.append(ProjectionPoint(
                date: date,
                nominal: balance,
                real: balance.scaled(by: Decimal(1) / deflator)
            ))
        }

        let years = yearSummaries(
            points: points,
            startingBalance: input.startingBalance,
            contributedByYear: contributedByYear,
            eventsByYear: eventsByYear,
            withdrawnByYear: withdrawnByYear,
            base: base,
            calendar: calendar
        )

        return ProjectionResult(
            points: points,
            years: years,
            milestones: milestones(in: years, input: input),
            depletion: depletion
        )
    }

    /// 그 달에 자산에서 꺼내야 하는 금액. 생활비 − 연금 소득, 음수면 0.
    ///
    /// 연금이 생활비보다 많은 달은 남는 돈을 자산에 더하지 않는다. 그건
    /// 은퇴 후 저축을 가정하는 셈이고, 여기서 낙관을 더할 이유가 없다.
    static func monthlyWithdrawal(
        _ input: ProjectionInput,
        year: Int,
        deflator: Decimal,
        base: CurrencyCode
    ) -> Money {
        guard !input.monthlyRetirementSpending.isZero else { return .zero(base) }
        let spending = input.monthlyRetirementSpending.scaled(by: deflator)

        var income = Money.zero(base)
        for stream in input.incomes where stream.isActive(inYear: year) {
            // 물가연동이 안 되는 연금은 액면가가 고정이다 — 오늘 돈으로는 계속 줄어든다.
            income += stream.isInflationLinked
                ? stream.monthlyAmount.scaled(by: deflator)
                : stream.monthlyAmount
        }

        let net = spending - income
        return net.minorUnits > 0 ? net : .zero(base)
    }

    /// 달력 연도별로 묶는다. 첫 해와 마지막 해는 부분 연도일 수 있다 — 정상이다.
    private static func yearSummaries(
        points: [ProjectionPoint],
        startingBalance: Money,
        contributedByYear: [Int: Money],
        eventsByYear: [Int: Money],
        withdrawnByYear: [Int: Money],
        base: CurrencyCode,
        calendar: Calendar
    ) -> [YearSummary] {
        var lastPointOfYear: [Int: Money] = [:]
        for point in points.dropFirst() {
            lastPointOfYear[calendar.component(.year, from: point.date)] = point.nominal
        }

        var summaries: [YearSummary] = []
        var previousEnd = startingBalance
        for year in lastPointOfYear.keys.sorted() {
            guard let end = lastPointOfYear[year] else { continue }
            let contributed = contributedByYear[year] ?? .zero(base)
            let events = eventsByYear[year] ?? .zero(base)
            let withdrawn = withdrawnByYear[year] ?? .zero(base)
            summaries.append(YearSummary(
                year: year,
                endBalance: end,
                contributed: contributed,
                cashEvents: events,
                withdrawn: withdrawn,
                gain: end - previousEnd - contributed - events + withdrawn
            ))
            previousEnd = end
        }
        return summaries
    }

    private static func milestones(in years: [YearSummary], input: ProjectionInput) -> [Milestone] {
        var result: [Milestone] = []

        // 첫 해는 부분 연도라 적립이 덜 들어간다. 판정에서 뺀다.
        if let crossing = years.dropFirst().first(where: { !$0.contributed.isZero && $0.gain > $0.contributed }) {
            result.append(Milestone(kind: .returnsExceedContribution,
                                    year: crossing.year, balance: crossing.endBalance))
        }

        let doubled = input.startingBalance.scaled(by: 2)
        if !input.startingBalance.isZero,
           let hit = years.first(where: { $0.endBalance >= doubled }) {
            result.append(Milestone(kind: .doubled, year: hit.year, balance: hit.endBalance))
        }

        // 연봉은 가만히 있지 않는다. **적립액 증가율과 같은 속도로 오른다고 본다** —
        // 그 값이 원래 "연봉 상승률" 이다. 오늘 돈 기준 연봉을 그 해까지 올린 뒤
        // 그 해 명목 수익과 견준다.
        if !input.annualIncome.isZero, let firstYear = years.first?.year {
            var salary = input.annualIncome
            let step = Decimal(1) + input.annualContributionGrowth.fraction
            for summary in years {
                if summary.year > firstYear { salary = salary.scaled(by: step) }
                // 첫 해는 부분 연도라 수익이 덜 잡힌다. 판정에서 뺀다.
                guard summary.year > firstYear, summary.gain >= salary else { continue }
                result.append(Milestone(kind: .returnsExceedSalary,
                                        year: summary.year, balance: summary.endBalance))
                break
            }
        }

        if let target = input.targetAmount, !target.isZero,
           let hit = years.first(where: { $0.endBalance >= target }) {
            result.append(Milestone(kind: .targetReached, year: hit.year, balance: hit.endBalance))
        }

        return result.sorted { $0.year < $1.year }
    }

    /// 연 수익률을 월 성장 배수로 바꾼다.
    ///
    /// 12제곱근은 `Decimal` 로 구할 수 없어 `Double` 을 거친다. 금액이 아니라
    /// 비율이므로 ADR-0003 의 예외에 해당한다. 다만 잡음을 그대로 들이지 않도록
    /// 소수 12자리로 고정한 뒤 `Decimal` 로 옮긴다.
    static func monthlyFactor(annual: Ratio) -> Decimal {
        guard annual != .zero else { return 1 }
        let yearly = NSDecimalNumber(decimal: annual.fraction).doubleValue
        return Decimals.fromDouble(pow(1 + yearly, 1.0 / 12.0))
    }
}
