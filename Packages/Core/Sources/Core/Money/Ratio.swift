import Foundation

/// 비율. basis point(1/10,000) 정수로 저장한다.
///
/// 기대수익률 8% = `Ratio(basisPoints: 800)`, 100% = `Ratio(basisPoints: 10_000)`.
public struct Ratio: Hashable, Sendable, Codable, Comparable {
    public let basisPoints: Int

    public init(basisPoints: Int) {
        self.basisPoints = basisPoints
    }

    public init(percent: Decimal, rounding: RoundingMode = .bankers) {
        self.basisPoints = Decimals.roundedInt(percent * 100, rounding: rounding)
    }

    public static let zero = Ratio(basisPoints: 0)
    public static let one = Ratio(basisPoints: 10_000)

    /// 0.08 형태
    public var fraction: Decimal { Decimal(basisPoints) / 10_000 }
    /// 8 형태
    public var percent: Decimal { Decimal(basisPoints) / 100 }

    public static func < (lhs: Ratio, rhs: Ratio) -> Bool {
        lhs.basisPoints < rhs.basisPoints
    }
}
