import Foundation

/// 결정론적 프로젝션의 입력.
///
/// 몬테카를로(신뢰구간 밴드)는 이 위에 얹는다. 먼저 중앙값 한 줄을 정확히 그린다.
public struct ProjectionInput: Sendable, Hashable {
    public var startDate: Date
    public var endDate: Date
    public var startingBalance: Money
    public var monthlyContribution: Money
    public var annualReturn: Ratio
    /// 적립액의 연 증가율 (연봉 상승률).
    public var annualContributionGrowth: Ratio
    public var inflation: Ratio

    public init(
        startDate: Date,
        endDate: Date,
        startingBalance: Money,
        monthlyContribution: Money,
        annualReturn: Ratio,
        annualContributionGrowth: Ratio = .zero,
        inflation: Ratio = .zero
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.startingBalance = startingBalance
        self.monthlyContribution = monthlyContribution
        self.annualReturn = annualReturn
        self.annualContributionGrowth = annualContributionGrowth
        self.inflation = inflation
    }
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

    public var first: ProjectionPoint? { points.first }
    public var last: ProjectionPoint? { points.last }

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
        let months = calendar.dateComponents([.month], from: input.startDate, to: input.endDate).month ?? 0
        guard months > 0 else {
            let single = ProjectionPoint(
                date: input.startDate,
                nominal: input.startingBalance,
                real: input.startingBalance
            )
            return ProjectionResult(points: [single])
        }

        let growth = monthlyFactor(annual: input.annualReturn)
        let inflation = monthlyFactor(annual: input.inflation)
        let contributionStep = Decimal(1) + input.annualContributionGrowth.fraction

        var balance = input.startingBalance
        var contribution = input.monthlyContribution
        var deflator = Decimal(1)

        var points: [ProjectionPoint] = [
            ProjectionPoint(date: input.startDate, nominal: balance, real: balance)
        ]
        points.reserveCapacity(months + 1)

        for month in 1...months {
            balance = (balance + contribution).scaled(by: growth)
            deflator *= inflation

            if month % 12 == 0 {
                contribution = contribution.scaled(by: contributionStep)
            }

            let date = calendar.date(byAdding: .month, value: month, to: input.startDate) ?? input.startDate
            points.append(ProjectionPoint(
                date: date,
                nominal: balance,
                real: balance.scaled(by: Decimal(1) / deflator)
            ))
        }

        return ProjectionResult(points: points)
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
