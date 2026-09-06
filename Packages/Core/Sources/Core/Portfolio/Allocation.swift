import Foundation

/// 목표 비중과 실제 비중의 차이.
///
/// **두 층으로 잰다** (docs/08-feedback.md 14번).
///
/// | 층 | 무엇을 나누나 | 분모 |
/// |---|---|---|
/// | 자산군 | 주식·ETF · 채권 · 금 · 예적금 · 현금 · 부동산 … | 그 사람의 **자산 합계**(부채 제외) |
/// | 종목 | 그 자산군 안의 종목들 | **그 자산군 합계** |
///
/// 한 종목의 전체 비중은 곱이다. 주식·ETF 60% × 그 안에서 VOO 40% = 24%.
/// 이렇게 나눠야 **종목을 하나 더 담아도 자산군 층이 흔들리지 않는다.**
///
/// 기준이 사람인 이유는 실제 데이터에 있다 — 같은 종목이 IRP·연금저축·ISA
/// 세 계좌에 흩어져 있어서, 계좌 안에서 재면 "이 사람이 미국 주식을 얼마나
/// 갖고 있나" 를 알 수 없다. **같은 이름은 합쳐서 판정한다.**
public enum Allocation {

    /// 한 줄의 판정 결과. 자산군 줄과 종목 줄이 같은 모양을 쓴다.
    public struct Slice: Sendable, Hashable, Identifiable {
        /// 자산군이면 자산군 이름, 종목이면 종목 이름.
        public let label: String
        /// 같은 이름으로 합친 실제 금액.
        public let amount: Money
        /// 실제 비중. 0.0~1.0
        public let actual: Decimal
        /// 목표 비중. **없으면 nil** — 그 자체가 알림거리다.
        public let target: Decimal?
        public let status: DriftStatus

        public var id: String { label }

        /// 목표에서 얼마나 벗어났나. 목표가 없으면 nil.
        public var drift: Decimal? {
            target.map { actual - $0 }
        }
    }

    public enum DriftStatus: Sendable, Hashable {
        /// 허용 오차 안.
        case onTrack
        /// 허용 오차를 벗어남.
        case watch
        /// 허용 오차의 두 배를 벗어남.
        case act
        /// 목표를 아직 안 정했다. **조용히 넘어가지 않는다** — 목표를 세우는
        /// 연습을 시키는 것도 이 앱이 하는 일이다.
        case noTarget

        public var label: String {
            switch self {
            case .onTrack: return "지킴"
            case .watch: return "주의"
            case .act: return "조치"
            case .noTarget: return "목표 없음"
            }
        }
    }

    /// 판정 기준. 목표가 작은 종목에 절대 오차만 쓰면 영영 안 걸리므로
    /// **절대와 상대 중 큰 쪽**을 쓴다.
    public struct Tolerance: Sendable, Hashable {
        /// 절대 허용 오차 (퍼센트포인트). 기본 5%p.
        public var absolute: Ratio
        /// 상대 허용 오차 (목표 대비). 기본 25%.
        public var relative: Ratio

        public init(absolute: Ratio = Ratio(basisPoints: 500),
                    relative: Ratio = Ratio(basisPoints: 2_500)) {
            self.absolute = absolute
            self.relative = relative
        }

        /// 목표가 `target` 일 때 실제로 허용되는 폭.
        public func allowed(for target: Decimal) -> Decimal {
            max(absolute.fraction, target * relative.fraction)
        }
    }

    /// 비중을 잴 한 덩어리.
    public struct Entry: Sendable, Hashable {
        /// 묶는 이름. 같은 이름끼리 합쳐진다.
        public let label: String
        public let amount: Money
        /// 이 덩어리의 목표. 여럿이 같은 이름이면 **합쳐서** 목표가 된다.
        public let targetBP: Int?

        public init(label: String, amount: Money, targetBP: Int?) {
            self.label = label
            self.amount = amount
            self.targetBP = targetBP
        }
    }

    /// 한 층을 잰다.
    ///
    /// 목표의 합이 100%가 아니어도 막지 않는다 — 적다 말면 100이 안 되는 것이
    /// 정상이다. 대신 **비례로 정규화해서** 판정한다. 그래야 "아직 60%만
    /// 적었는데 전부 미달" 이라는 거짓 경고가 안 뜬다.
    public static func slices(_ entries: [Entry],
                              tolerance: Tolerance = Tolerance()) -> [Slice] {
        guard !entries.isEmpty else { return [] }
        let currency = entries[0].amount.currency

        // 같은 이름을 합친다. 금액도 목표도 함께 더한다.
        var order: [String] = []
        var amounts: [String: Int] = [:]
        var targets: [String: Int?] = [:]
        for entry in entries {
            if amounts[entry.label] == nil {
                order.append(entry.label)
                amounts[entry.label] = 0
                targets[entry.label] = Int?.none
            }
            amounts[entry.label]! += entry.amount.minorUnits
            if let bp = entry.targetBP {
                targets[entry.label] = (targets[entry.label] ?? nil).map { $0 + bp } ?? bp
            }
        }

        let total = amounts.values.reduce(0, +)
        guard total > 0 else { return [] }

        // 적어 둔 목표의 합. 100%가 아니면 이 값으로 정규화한다.
        let targetSum = order.reduce(0) { $0 + ((targets[$1] ?? nil) ?? 0) }

        return order.map { label in
            let amount = amounts[label] ?? 0
            let actual = Decimal(amount) / Decimal(total)
            let bp = targets[label] ?? nil
            let target: Decimal? = bp.flatMap { value in
                guard targetSum > 0 else { return nil }
                return Decimal(value) / Decimal(targetSum)
            }
            return Slice(
                label: label,
                amount: Money(minorUnits: amount, currency: currency),
                actual: actual,
                target: target,
                status: status(actual: actual, target: target, tolerance: tolerance)
            )
        }
    }

    static func status(actual: Decimal, target: Decimal?, tolerance: Tolerance) -> DriftStatus {
        guard let target else { return .noTarget }
        let gap = abs(actual - target)
        let allowed = tolerance.allowed(for: target)
        if gap <= allowed { return .onTrack }
        return gap <= allowed * 2 ? .watch : .act
    }

    /// **팔지 않고 적립으로 맞춘다.**
    ///
    /// 리밸런싱은 보통 비싼 것을 팔아 싼 것을 사지만, 매도는 세금과 수수료가
    /// 들고 무엇을 팔지는 앱이 판단할 일이 아니다. 대신 이번에 넣을 돈을
    /// **어디에 얼마씩 나누면 목표에 가장 가까워지는지**를 답한다.
    ///
    /// 방법은 단순하다. 넣고 난 뒤의 목표 금액(`(총액 + 적립) × 목표비중`)에서
    /// 지금 금액을 뺀 **모자란 만큼**에 비례해 나눈다. 이미 목표를 넘긴 곳에는
    /// 넣지 않는다 — 그게 자연스럽게 비중을 되돌린다.
    public static func contributionSplit(_ slices: [Slice],
                                         contribution: Money) -> [(label: String, amount: Money)] {
        guard contribution.minorUnits > 0 else { return [] }
        let currency = contribution.currency
        let total = slices.reduce(0) { $0 + $1.amount.minorUnits }
        let after = Decimal(total + contribution.minorUnits)

        // 넣고 난 뒤 있어야 할 금액에서 지금을 뺀 부족분.
        var shortfalls: [(String, Decimal)] = []
        for slice in slices {
            guard let target = slice.target else { continue }
            let want = after * target
            let gap = want - Decimal(slice.amount.minorUnits)
            if gap > 0 { shortfalls.append((slice.label, gap)) }
        }
        let sum = shortfalls.reduce(Decimal(0)) { $0 + $1.1 }
        guard sum > 0 else { return [] }

        // 비례 배분 뒤 1원 단위 잔돈은 가장 많이 모자란 곳에 얹는다.
        var result: [(label: String, amount: Money)] = []
        var assigned = 0
        for (label, gap) in shortfalls {
            let share = Decimals.roundedInt(Decimal(contribution.minorUnits) * gap / sum,
                                            rounding: .bankers)
            result.append((label, Money(minorUnits: share, currency: currency)))
            assigned += share
        }
        if let index = shortfalls.enumerated().max(by: { $0.element.1 < $1.element.1 })?.offset {
            let remainder = contribution.minorUnits - assigned
            if remainder != 0 {
                result[index].amount += Money(minorUnits: remainder, currency: currency)
            }
        }
        return result.filter { $0.amount.minorUnits > 0 }
    }
}
