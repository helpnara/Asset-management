import Foundation

/// ISO 4217 통화 코드.
public struct CurrencyCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let code: String

    public init(_ code: String) {
        self.code = code.uppercased()
    }

    public static let krw = CurrencyCode("KRW")
    public static let usd = CurrencyCode("USD")
    public static let jpy = CurrencyCode("JPY")
    public static let eur = CurrencyCode("EUR")

    /// 최소 단위의 10의 지수. 원·엔은 보조 단위가 없어 0, 달러는 센트라서 2.
    public var minorUnitExponent: Int {
        switch code {
        case "KRW", "JPY", "VND", "CLP", "ISK": return 0
        default: return 2
        }
    }

    public var description: String { code }
}

extension CurrencyCode {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}
