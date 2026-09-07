import Foundation

/// 목표 비중과 실제 비중의 차이.
///
/// **비중은 네 층으로 잰다** (docs/08-feedback.md 15번).
///
/// | 층 | 무엇을 나누나 | 분모 | 목표 |
/// |---|---|---|---|
/// | 가족 | 구성원 | 가족 자산 합계 | 없음 |
/// | 구성원 | 계좌 | 그 사람의 자산 합계 | 없음 |
/// | 계좌 | 종목 | **그 계좌의 합계** | **있음 — 합이 100%** |
/// | (별도) | 지역 · 자산군 | 가족 자산 합계 | 있음 |
///
/// 목표가 붙는 곳은 **계좌 안의 종목**뿐이다. 계좌마다 투자 목적과 규모가 다르니
/// "이 계좌를 무엇으로 채울 것인가" 가 실제로 사람이 정하는 단위이기 때문이다.
/// 위의 두 층(가족→구성원, 구성원→계좌)은 목표를 둘 수 없다 — 계좌 잔고는
/// 급여와 한도가 정하는 것이라 사람이 비율로 고를 수 있는 값이 아니다.
///
/// 그와 **별개로** 가족 전체를 지역(미국·한국)과 자산군(부동산·주식·채권·금·연금)
/// 으로 갈라 본다. 이쪽은 계좌 구조를 가로지르는 질문이다.
///
/// **목표는 적은 그대로 쓴다 — 정규화하지 않는다.** 한때 목표 합으로 나눠
/// 비례 배분했는데, 그러면 20% 라고 적은 종목이 화면에는 33% 로 보였다.
/// 사용자가 요구한 표기는 `15/20%` — 적은 값이 그대로 보여야 한다.
/// 합이 100%가 아니면 숨기지 말고 **합계를 눈에 띄게 적는다**.
public enum Allocation {

    /// 한 줄의 판정 결과. 자산군 줄과 종목 줄이 같은 모양을 쓴다.
    public struct Slice: Sendable, Hashable, Identifiable {
        /// 자산군이면 자산군 이름, 종목이면 종목 이름.
        public let label: String
        /// 같은 이름으로 합친 실제 금액.
        public let amount: Money
        /// 실제 비중. 0.0~1.0
        public let actual: Decimal
        /// 목표 비중. **적은 그대로**다 (정규화하지 않는다).
        /// 없으면 nil — 그 자체가 알림거리다.
        public let target: Decimal?
        public let status: DriftStatus

        public var id: String { label }

        /// 목표에서 얼마나 벗어났나. 목표가 없으면 nil.
        public var drift: Decimal? {
            target.map { actual - $0 }
        }

        /// 사용자가 요구한 표기 — `15/20%`. 목표가 없으면 실제만 `15%`.
        ///
        /// 한 줄에 실제와 목표가 같이 서야 "지금 어떤 상황인지" 를 배지 없이도
        /// 읽을 수 있다. 조치·주의만으로는 얼마나 벗어났는지 알 수 없었다.
        public var comparisonLabel: String {
            let now = PercentFormatter.oneDecimal(actual)
            guard let target else { return "\(now)%" }
            return "\(now)/\(PercentFormatter.oneDecimal(target))%"
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
    /// 목표의 합이 100%가 아니어도 막지 않는다. 대신 **적은 그대로** 판정하고,
    /// 합이 얼마인지는 `targetSumBP` 로 따로 알려 화면이 눈에 띄게 적게 한다.
    /// 정규화하지 않는 이유는 이 타입 맨 위에 적어 두었다.
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

        return order.map { label in
            let amount = amounts[label] ?? 0
            let actual = Decimal(amount) / Decimal(total)
            let bp = targets[label] ?? nil
            let target: Decimal? = bp.map { Decimal($0) / 10_000 }
            return Slice(
                label: label,
                amount: Money(minorUnits: amount, currency: currency),
                actual: actual,
                target: target,
                status: status(actual: actual, target: target, tolerance: tolerance)
            )
        }
    }

    /// 적어 둔 목표의 합 (basis point). 100%(10,000)가 아니면 화면이 그렇게 적는다.
    ///
    /// 같은 이름은 합쳐서 센다 — `slices` 와 같은 규칙이어야 화면의 두 숫자가
    /// 어긋나지 않는다.
    public static func targetSumBP(_ entries: [Entry]) -> Int {
        var byLabel: [String: Int] = [:]
        for entry in entries {
            guard let bp = entry.targetBP else { continue }
            byLabel[entry.label, default: 0] += bp
        }
        return byLabel.values.reduce(0, +)
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
