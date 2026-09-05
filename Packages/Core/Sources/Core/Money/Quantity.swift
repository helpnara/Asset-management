import Foundation

/// 보유 수량. 소수점 8자리 고정 스케일의 정수로 표현한다.
///
/// 8자리는 암호화폐(satoshi)까지 손실 없이 담기 위한 값이며,
/// `Money`와 같은 이유로 정수로 저장한다 (ADR-0003).
public struct Quantity: Hashable, Sendable, Codable, Comparable {
    public static let scale = 8

    public let scaled: Int

    public init(scaled: Int) {
        self.scaled = scaled
    }

    public init(_ value: Decimal, rounding: RoundingMode = .bankers) {
        self.scaled = Decimals.roundedInt(value * Quantity.factor, rounding: rounding)
    }

    public init(_ value: Int) {
        self.init(Decimal(value))
    }

    public static let zero = Quantity(scaled: 0)

    static var factor: Decimal { Decimals.powerOfTen(Quantity.scale) }

    public var value: Decimal {
        Decimal(scaled) / Quantity.factor
    }

    public var isZero: Bool { scaled == 0 }

    public static func < (lhs: Quantity, rhs: Quantity) -> Bool {
        lhs.scaled < rhs.scaled
    }

    public static func + (lhs: Quantity, rhs: Quantity) -> Quantity {
        Quantity(scaled: lhs.scaled + rhs.scaled)
    }

    public static func - (lhs: Quantity, rhs: Quantity) -> Quantity {
        Quantity(scaled: lhs.scaled - rhs.scaled)
    }

    /// 단가를 곱해 평가액을 낸다.
    public func value(atUnitPrice price: Money, rounding: RoundingMode = .bankers) -> Money {
        Money(price.amount * value, currency: price.currency, rounding: rounding)
    }
}
