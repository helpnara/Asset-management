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
        /// 화면에 적는 정수 퍼센트. **같은 층의 합이 정확히 100 이 되도록**
        /// 최대잔여법으로 맞춰 둔다 (docs/08-feedback.md 18번).
        ///
        /// 줄마다 따로 반올림하면 `32 + 8 + 16 + 7 + 38 = 101` 처럼 어긋난다.
        /// 비중 화면에서 합이 100 이 아닌 것은 그 자체로 틀려 보인다.
        public let actualPercent: Int
        /// 목표의 정수 퍼센트. 입력이 1%p 단위라 반올림이 필요 없다.
        public let targetPercent: Int?
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
            guard let targetPercent else { return "\(actualPercent)%" }
            return "\(actualPercent)/\(targetPercent)%"
        }
    }

    /// 목표 대비 어느 쪽으로 얼마나 벗어났나 (docs/08-feedback.md 20번).
    ///
    /// 예전에는 `주의`·`조치` 두 단계였는데, **어느 쪽으로 벗어났는지**를
    /// 말해 주지 않아서 배지를 봐도 무엇을 해야 할지 알 수 없었다.
    /// 이제 방향을 말한다 — 넘쳤으면 `초과`, 모자라면 `부족`.
    ///
    /// **허용 오차 안이면 아무 말도 안 한다.** 지킴 배지를 달면 화면이
    /// 배지로 뒤덮이는데, 지키고 있는 것은 원래 조용해야 한다.
    public enum DriftStatus: Sendable, Hashable {
        /// 허용 오차 안. **화면에 아무것도 안 띄운다.**
        case onTrack
        /// 목표보다 많다.
        case over
        /// 목표보다 적다.
        case under
        /// 목표를 아직 안 정했다. **조용히 넘어가지 않는다** — 목표를 세우는
        /// 연습을 시키는 것도 이 앱이 하는 일이다.
        case noTarget

        public var label: String {
            switch self {
            case .onTrack: return ""
            case .over: return "초과"
            case .under: return "부족"
            case .noTarget: return "목표 없음"
            }
        }

        /// 목표에서 벗어났나. 진단이 셀 때 쓴다.
        public var isDrifting: Bool { self == .over || self == .under }
    }

    /// 판정 기준 — **퍼센트포인트 하나**다 (docs/08-feedback.md 20번).
    ///
    /// 예전에는 절대와 상대 중 큰 쪽을 썼는데, 두 숫자가 어떻게 맞물리는지
    /// 설명하기 어렵고 사용자가 조절하기도 어려웠다. **목표 비중을 지키는 것이
    /// 중요하다**는 것이 사용자의 판단이라, 기준은 좁고 단순한 편이 낫다.
    ///
    /// 기본 ±3%p — 목표 20%인 종목은 17~23% 안에 있으면 지키는 것으로 본다.
    public struct Tolerance: Sendable, Hashable {
        /// 허용 오차 (퍼센트포인트). 기본 3%p.
        public var absolute: Ratio

        public init(absolute: Ratio = Ratio(basisPoints: 300)) {
            self.absolute = absolute
        }

        /// 실제로 허용되는 폭. 목표 크기와 무관하게 같다.
        public var allowed: Decimal { absolute.fraction }
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

        // 정수 퍼센트는 **줄마다 따로** 반올림하면 합이 100 이 안 된다.
        // 최대잔여법으로 한꺼번에 맞춘다.
        let percents = integerPercents(order.map { Decimal(amounts[$0] ?? 0) / Decimal(total) })

        return zip(order, percents).map { label, percent in
            let amount = amounts[label] ?? 0
            let actual = Decimal(amount) / Decimal(total)
            let bp = targets[label] ?? nil
            let target: Decimal? = bp.map { Decimal($0) / 10_000 }
            return Slice(
                label: label,
                amount: Money(minorUnits: amount, currency: currency),
                actual: actual,
                target: target,
                actualPercent: percent,
                targetPercent: bp.map { Int((Double($0) / 100).rounded()) },
                status: status(actual: actual, target: target, tolerance: tolerance)
            )
        }
    }

    /// 비율들을 정수 퍼센트로 바꾸되 **합이 정확히 100 이 되게** 한다.
    ///
    /// 최대잔여법(Hamilton). 먼저 다 내림하고, 남은 자리를 소수부가 큰 것부터
    /// 하나씩 나눠 준다. 선거구 의석을 나누는 그 방법이고, 여기서 필요한 성질도
    /// 같다 — **각자 제 값에 가장 가깝게, 그러면서 총합이 딱 맞게.**
    ///
    /// 합이 100 이 아닌 값들(예: 목표를 덜 적어 60%뿐)에는 쓰지 않는다.
    /// 그때는 100 으로 부풀리는 것이 거짓말이 된다.
    public static func integerPercents(_ fractions: [Decimal]) -> [Int] {
        guard !fractions.isEmpty else { return [] }
        let sum = fractions.reduce(Decimal(0), +)
        // 합이 1 이 아니면(=한 층이 아니면) 그냥 각자 반올림한다.
        guard abs(sum - 1) < Decimal(string: "0.0001")! else {
            return fractions.map { Decimals.roundedInt($0 * 100, rounding: .plain) }
        }

        let scaled = fractions.map { $0 * 100 }
        var result = scaled.map { Decimals.roundedInt($0, rounding: .down) }
        var remaining = 100 - result.reduce(0, +)
        guard remaining > 0 else { return result }

        // 소수부가 큰 것부터. 같으면 앞선 것에 준다 — 순서가 정해져야 결과가 늘 같다.
        let order = scaled.enumerated()
            .map { (index: $0.offset, fraction: $0.element - Decimal(result[$0.offset])) }
            .sorted { $0.fraction == $1.fraction ? $0.index < $1.index : $0.fraction > $1.fraction }

        for entry in order where remaining > 0 {
            result[entry.index] += 1
            remaining -= 1
        }
        return result
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
        let gap = actual - target
        if abs(gap) <= tolerance.allowed { return .onTrack }
        return gap > 0 ? .over : .under
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
