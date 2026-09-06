import Foundation

/// 시드를 고정할 수 있는 난수 생성기 (SplitMix64).
///
/// 시스템 생성기는 시드를 못 박아서 같은 입력에 매번 다른 그림이 나온다.
/// 사용자가 아무것도 안 바꿨는데 밴드가 흔들리면 그건 결함으로 읽힌다.
/// 테스트 재현성도 여기서 나온다.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Box–Muller 변환으로 표준정규분포를 뽑는다.
    mutating func nextNormal() -> Double {
        // log(0) 을 피하려고 아주 작은 값을 하한으로 둔다.
        let u1 = Double.random(in: 1e-12...1, using: &self)
        let u2 = Double.random(in: 0...1, using: &self)
        return (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * .pi * u2)
    }
}

public struct MonteCarloInput: Sendable {
    public var base: ProjectionInput
    /// 연 변동성. 주식 위주 포트폴리오면 15~18% 정도다.
    public var annualVolatility: Ratio
    public var paths: Int
    public var seed: UInt64

    public init(base: ProjectionInput, annualVolatility: Ratio, paths: Int = 1_000, seed: UInt64 = 20_260_905) {
        self.base = base
        self.annualVolatility = annualVolatility
        self.paths = paths
        self.seed = seed
    }
}

/// 한 시점의 분포. 신뢰구간 밴드가 이걸 잇는다.
public struct MonteCarloBand: Sendable, Hashable {
    public let date: Date
    public let p10: Money
    public let p50: Money
    public let p90: Money
}

public struct MonteCarloResult: Sendable, Hashable {
    public let bands: [MonteCarloBand]
    /// 목표 금액을 넘길 확률. 목표가 없으면 nil.
    public let successProbability: Double?
    public let paths: Int
}

/// 변동성을 반영한 시뮬레이션.
///
/// **금액을 `Double` 로 굴린다.** ADR-0003 은 금액에 `Double` 을 금지하지만
/// 여기는 예외다 — 결과 자체가 확률 분포라 원 단위 정확도가 의미를 갖지 않는다.
/// 정확한 중앙값이 필요하면 `Projection.run` 의 결정론적 결과를 쓴다.
/// 이 둘을 섞지 않는 것이 중요하다.
public enum MonteCarlo {

    public static func run(_ input: MonteCarloInput, calendar: Calendar = .current) -> MonteCarloResult {
        let base = input.base
        let currency = base.startingBalance.currency
        let months = calendar.dateComponents([.month], from: base.startDate, to: base.endDate).month ?? 0
        guard months > 0, input.paths > 0 else {
            return MonteCarloResult(bands: [], successProbability: nil, paths: 0)
        }

        // 연 수익률·변동성을 월 단위로 바꾼다. 변동성은 시간의 제곱근에 비례한다.
        let monthlySigma = NSDecimalNumber(decimal: input.annualVolatility.fraction).doubleValue / 12.0.squareRoot()

        // 덩어리마다 자기 속도로 굴린다. **변동성은 투자자산에만 붙인다** —
        // 전세보증금이 ±15% 로 흔들리면 밴드가 거짓말을 한다
        // (docs/08-feedback.md 3번 (d) · 11번).
        let startBalances = base.buckets.map { Double($0.amount.minorUnits) }
        let bucketMeans = base.buckets.map { bucket -> Double in
            let annual = NSDecimalNumber(decimal: bucket.annualReturn.fraction).doubleValue
            return pow(1 + annual, 1.0 / 12.0) - 1
        }
        let volatileIndex = base.buckets.firstIndex { $0.profile == .investment }
        let inflowIndex = volatileIndex ?? 0
        let drawdownOrder = base.buckets.indices.sorted {
            base.buckets[$0].profile.drawdownOrder < base.buckets[$1].profile.drawdownOrder
        }

        // 인출액과 적립/인출 구간의 경계는 경로마다 같다. 1,000번 다시 세지 않고
        // 한 번만 계산해 둔다. **예상선과 같은 식**(Projection.monthlyWithdrawal)을
        // 쓰는 것이 중요하다 — 다른 식을 쓰면 선과 밴드가 서로 다른 말을 한다.
        let inflationFactor = Projection.monthlyFactor(annual: base.inflation)
        var deflator = Decimal(1)
        var isAccumulating = [Bool](repeating: true, count: months + 1)
        var withdrawalByMonth = [Double](repeating: 0, count: months + 1)
        for month in 1...months {
            let date = calendar.date(byAdding: .month, value: month, to: base.startDate) ?? base.startDate
            deflator *= inflationFactor
            isAccumulating[month] = date <= base.retirementDate
            guard !isAccumulating[month] else { continue }
            let year = calendar.component(.year, from: date)
            withdrawalByMonth[month] = Double(
                Projection.monthlyWithdrawal(base, year: year, deflator: deflator, base: currency).minorUnits
            )
        }

        let baseContribution = Double(base.monthlyContribution.minorUnits)
        let contributionStep = 1 + NSDecimalNumber(decimal: base.annualContributionGrowth.fraction).doubleValue

        var eventsByMonth: [Int: Double] = [:]
        for event in base.cashEvents {
            let offset = calendar.dateComponents([.month], from: base.startDate, to: event.date).month ?? -1
            guard offset >= 1, offset <= months else { continue }
            eventsByMonth[offset, default: 0] += Double(event.amount.minorUnits)
        }

        // 연말에만 표본을 남긴다. 매달 남기면 메모리와 정렬 비용만 커진다.
        let sampleMonths = (1...months).filter { month in
            month == months || isYearEnd(month: month, from: base.startDate, calendar: calendar)
        }
        var samples: [[Double]] = Array(repeating: [], count: sampleMonths.count)
        for index in samples.indices { samples[index].reserveCapacity(input.paths) }

        var finals: [Double] = []
        finals.reserveCapacity(input.paths)

        var generator = SeededGenerator(seed: input.seed)

        for _ in 0..<input.paths {
            var balances = startBalances
            var contribution = baseContribution
            var sampleIndex = 0

            for month in 1...months {
                // 달마다 한 번만 뽑는다. 덩어리 수가 늘어도 같은 시드에서
                // 같은 그림이 나오게 하려는 것이다.
                let shock = generator.nextNormal()
                let event = eventsByMonth[month] ?? 0

                if isAccumulating[month] {
                    balances[inflowIndex] += contribution + event
                } else {
                    balances[inflowIndex] += event
                    // 투자자산부터 꺼낸다. 예상선과 같은 순서다.
                    var remaining = withdrawalByMonth[month]
                    for index in drawdownOrder where remaining > 0 {
                        let take = min(balances[index], remaining)
                        guard take > 0 else { continue }
                        balances[index] -= take
                        remaining -= take
                    }
                }

                for index in balances.indices {
                    var factor = 1 + bucketMeans[index]
                    if index == volatileIndex { factor += monthlySigma * shock }
                    balances[index] *= factor
                    if balances[index] < 0 { balances[index] = 0 }   // 빚으로 굴러가지는 않는다
                }
                if month % 12 == 0 { contribution *= contributionStep }

                if sampleIndex < sampleMonths.count, sampleMonths[sampleIndex] == month {
                    samples[sampleIndex].append(balances.reduce(0, +))
                    sampleIndex += 1
                }
            }
            finals.append(balances.reduce(0, +))
        }

        let bands = zip(sampleMonths, samples).map { month, values -> MonteCarloBand in
            let sorted = values.sorted()
            let date = calendar.date(byAdding: .month, value: month, to: base.startDate) ?? base.startDate
            return MonteCarloBand(
                date: date,
                p10: money(percentile(sorted, 0.10), currency),
                p50: money(percentile(sorted, 0.50), currency),
                p90: money(percentile(sorted, 0.90), currency)
            )
        }

        var success: Double?
        if let target = base.targetAmount, !target.isZero {
            let threshold = Double(target.minorUnits)
            success = Double(finals.filter { $0 >= threshold }.count) / Double(finals.count)
        }

        return MonteCarloResult(bands: bands, successProbability: success, paths: input.paths)
    }

    private static func isYearEnd(month: Int, from start: Date, calendar: Calendar) -> Bool {
        guard
            let current = calendar.date(byAdding: .month, value: month, to: start),
            let next = calendar.date(byAdding: .month, value: month + 1, to: start)
        else { return false }
        return calendar.component(.year, from: current) != calendar.component(.year, from: next)
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func money(_ value: Double, _ currency: CurrencyCode) -> Money {
        Money(minorUnits: Int(value.rounded()), currency: currency)
    }
}
