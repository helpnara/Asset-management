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

public struct ProjectionInput: Sendable, Hashable {
    public var startDate: Date
    public var endDate: Date
    public var startingBalance: Money
    public var monthlyContribution: Money
    public var annualReturn: Ratio
    /// 적립액의 연 증가율 (연봉 상승률).
    public var annualContributionGrowth: Ratio
    public var inflation: Ratio
    public var cashEvents: [CashEventInput]
    /// 마일스톤 판정에 쓴다. nil이면 목표 도달을 찾지 않는다.
    public var targetAmount: Money?

    public init(
        startDate: Date,
        endDate: Date,
        startingBalance: Money,
        monthlyContribution: Money,
        annualReturn: Ratio,
        annualContributionGrowth: Ratio = .zero,
        inflation: Ratio = .zero,
        cashEvents: [CashEventInput] = [],
        targetAmount: Money? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.startingBalance = startingBalance
        self.monthlyContribution = monthlyContribution
        self.annualReturn = annualReturn
        self.annualContributionGrowth = annualContributionGrowth
        self.inflation = inflation
        self.cashEvents = cashEvents
        self.targetAmount = targetAmount
    }
}

/// 한 해의 결산. 로드맵 타임라인과 마일스톤 판정이 이걸 읽는다.
public struct YearSummary: Sendable, Hashable {
    public let year: Int
    public let endBalance: Money
    public let contributed: Money
    public let cashEvents: Money
    /// 그 해 수익 = 연말 − 연초 − 적립 − 목돈.
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
    /// 목표 금액 도달.
    case targetReached

    public var label: String {
        switch self {
        case .returnsExceedContribution: return "수익 > 적립금"
        case .doubled: return "자산 2배"
        case .targetReached: return "목표 달성"
        }
    }

    public var detail: String {
        switch self {
        case .returnsExceedContribution: return "복리가 적립보다 많이 번다"
        case .doubled: return "시작 자산의 두 배"
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
            return ProjectionResult(points: [single], years: [], milestones: [])
        }

        let growth = monthlyFactor(annual: input.annualReturn)
        let inflation = monthlyFactor(annual: input.inflation)
        let contributionStep = Decimal(1) + input.annualContributionGrowth.fraction

        // 목돈은 그 달에 한 번 적용한다. 같은 달에 여러 건이면 합쳐서 넣는다.
        var eventsByMonth: [Int: Money] = [:]
        for event in input.cashEvents {
            let offset = calendar.dateComponents([.month], from: input.startDate, to: event.date).month ?? -1
            guard offset >= 1, offset <= months else { continue }
            eventsByMonth[offset, default: .zero(base)] += event.amount
        }

        var balance = input.startingBalance
        var contribution = input.monthlyContribution
        var deflator = Decimal(1)
        var contributedByYear: [Int: Money] = [:]
        var eventsByYear: [Int: Money] = [:]

        var points: [ProjectionPoint] = [
            ProjectionPoint(date: input.startDate, nominal: balance, real: balance)
        ]
        points.reserveCapacity(months + 1)

        for month in 1...months {
            let date = calendar.date(byAdding: .month, value: month, to: input.startDate) ?? input.startDate
            let year = calendar.component(.year, from: date)
            let event = eventsByMonth[month] ?? .zero(base)

            contributedByYear[year, default: .zero(base)] += contribution
            if !event.isZero { eventsByYear[year, default: .zero(base)] += event }

            balance = (balance + contribution + event).scaled(by: growth)
            deflator *= inflation

            if month % 12 == 0 {
                contribution = contribution.scaled(by: contributionStep)
            }

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
            base: base,
            calendar: calendar
        )

        return ProjectionResult(
            points: points,
            years: years,
            milestones: milestones(in: years, input: input)
        )
    }

    /// 달력 연도별로 묶는다. 첫 해와 마지막 해는 부분 연도일 수 있다 — 정상이다.
    private static func yearSummaries(
        points: [ProjectionPoint],
        startingBalance: Money,
        contributedByYear: [Int: Money],
        eventsByYear: [Int: Money],
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
            summaries.append(YearSummary(
                year: year,
                endBalance: end,
                contributed: contributed,
                cashEvents: events,
                gain: end - previousEnd - contributed - events
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
