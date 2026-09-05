import Foundation

/// 통화 최소 단위의 정수로 표현한 금액.
///
/// `Double`을 쓰지 않는 이유와 `Decimal`을 저장하지 않는 이유는 ADR-0003 참고.
/// 요약: CloudKit에 `Decimal` 대응 타입이 없어 미러링 과정에서 `Double`로 내려가고,
/// 30년치 복리를 곱하는 이 앱에서는 그 손실이 눈에 보인다.
public struct Money: Hashable, Sendable, Codable {
    /// 통화의 최소 단위 개수. KRW면 원, USD면 센트.
    public let minorUnits: Int
    public let currency: CurrencyCode

    public init(minorUnits: Int, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// 사람이 읽는 단위의 값. 표시와 비율 계산의 경계에서만 쓴다.
    public init(_ amount: Decimal, currency: CurrencyCode, rounding: RoundingMode = .bankers) {
        let scaled = amount * Decimals.powerOfTen(currency.minorUnitExponent)
        self.init(minorUnits: Decimals.roundedInt(scaled, rounding: rounding), currency: currency)
    }

    public init(_ amount: Int, currency: CurrencyCode) {
        self.init(Decimal(amount), currency: currency)
    }

    public static func zero(_ currency: CurrencyCode) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    public var amount: Decimal {
        Decimal(minorUnits) / Decimals.powerOfTen(currency.minorUnitExponent)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }
    public var magnitude: Money { Money(minorUnits: abs(minorUnits), currency: currency) }
}

// MARK: - 산술

extension Money {
    /// 통화가 다른 금액을 더하는 것은 프로그래머 실수다. 조용히 넘기지 않는다.
    private static func requireSameCurrency(_ lhs: Money, _ rhs: Money, _ op: String) {
        precondition(
            lhs.currency == rhs.currency,
            "통화가 다른 금액에 \(op)를 적용할 수 없습니다: \(lhs.currency) vs \(rhs.currency). converted(to:rate:)로 먼저 환산하세요."
        )
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        requireSameCurrency(lhs, rhs, "+")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        requireSameCurrency(lhs, rhs, "-")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits, currency: value.currency)
    }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        requireSameCurrency(lhs, rhs, "<")
        return lhs.minorUnits < rhs.minorUnits
    }

    /// 비율을 곱한다. 수익률·기대수익률·What-if 배수에 쓴다.
    public func scaled(by factor: Decimal, rounding: RoundingMode = .bankers) -> Money {
        Money(
            minorUnits: Decimals.roundedInt(Decimal(minorUnits) * factor, rounding: rounding),
            currency: currency
        )
    }

    public func scaled(by ratio: Ratio, rounding: RoundingMode = .bankers) -> Money {
        scaled(by: ratio.fraction, rounding: rounding)
    }

    /// 다른 통화로 환산한다. 환율은 사용자가 입력한 값이다 (ADR-0005 — 외부에서 가져오지 않는다).
    public func converted(
        to target: CurrencyCode,
        rate: Decimal,
        rounding: RoundingMode = .bankers
    ) -> Money {
        guard currency != target else { return self }
        return Money(amount * rate, currency: target, rounding: rounding)
    }

    /// 전체 대비 비중. 분모가 0이면 nil.
    public func share(of total: Money) -> Decimal? {
        Money.requireSameCurrency(self, total, "share(of:)")
        guard total.minorUnits != 0 else { return nil }
        return Decimal(minorUnits) / Decimal(total.minorUnits)
    }
}

extension Money: Comparable {}

extension Sequence where Element == Money {
    /// 같은 통화의 금액을 합산한다. 비어 있으면 0.
    public func total(in currency: CurrencyCode) -> Money {
        reduce(Money.zero(currency)) { $0 + $1 }
    }
}
