import Foundation

/// 한국식 금액 표기.
///
/// 화면 규칙(설계 문서 2.7): 큰 금액은 `3억 273만` 형태로 축약하고,
/// 표 안의 상세는 `302,731,078원`처럼 원 단위로 적는다. 두 표기를 한 화면에서 섞지 않는다.
public enum KoreanAmountFormatter {
    public enum SignStyle: Sendable {
        /// 부호를 붙이지 않는다 (음수는 `-`).
        case negativeOnly
        /// 증감 표시용. 양수에도 `+`를 붙인다.
        case always
    }

    private static let eok = 100_000_000
    private static let man = 10_000

    // MARK: - 원 단위 상세

    /// `302,731,078원`
    public static func full(_ money: Money, suffix: String = "원", sign: SignStyle = .negativeOnly) -> String {
        guard money.currency == .krw else { return foreign(money, sign: sign) }
        return signPrefix(money.minorUnits, sign) + grouped(abs(money.minorUnits)) + suffix
    }

    // MARK: - 억 + 만 축약

    /// `3억 273만` · `2억 5,310만` · `1,531만` · `8,200원`
    public static func abbreviated(_ money: Money, suffix: String = "", sign: SignStyle = .negativeOnly) -> String {
        guard money.currency == .krw else { return foreign(money, sign: sign) }
        let value = abs(money.minorUnits)
        let prefix = signPrefix(money.minorUnits, sign)

        let eokPart = value / eok
        let manPart = (value % eok) / man
        let wonPart = value % man

        if eokPart > 0 {
            let head = "\(grouped(eokPart))억"
            return prefix + (manPart > 0 ? "\(head) \(grouped(manPart))만\(suffix)" : head + suffix)
        }
        if manPart > 0 {
            return prefix + "\(grouped(manPart))만" + suffix
        }
        return prefix + grouped(wonPart) + (suffix.isEmpty ? "원" : suffix)
    }

    // MARK: - 한 단위 축약 (차트 · 로드맵)

    /// `3.0억` · `59.1억` · `5,310만` · `8,200원`
    ///
    /// 궤적 차트와 로드맵 타임라인처럼 자리가 좁고 자릿수보다 규모가 중요한 곳에 쓴다.
    public static func compact(_ money: Money, sign: SignStyle = .negativeOnly) -> String {
        guard money.currency == .krw else { return foreign(money, sign: sign) }
        let value = abs(money.minorUnits)
        let prefix = signPrefix(money.minorUnits, sign)

        if value >= eok {
            let tenths = Decimals.roundedInt(Decimal(value) / Decimal(eok) * 10, rounding: .plain)
            return prefix + "\(grouped(tenths / 10)).\(tenths % 10)억"
        }
        if value >= man {
            return prefix + "\(grouped(value / man))만"
        }
        return prefix + grouped(value) + "원"
    }

    // MARK: - 보조

    private static func signPrefix(_ minorUnits: Int, _ style: SignStyle) -> String {
        if minorUnits < 0 { return "-" }
        return style == .always && minorUnits > 0 ? "+" : ""
    }

    private static func foreign(_ money: Money, sign: SignStyle) -> String {
        var divisor = 1
        for _ in 0..<money.currency.minorUnitExponent { divisor *= 10 }
        let whole = abs(money.minorUnits) / divisor
        return signPrefix(money.minorUnits, sign) + grouped(whole) + " " + money.currency.code
    }

    /// `1234567` → `1,234,567`
    public static func grouped(_ value: Int) -> String {
        let isNegative = value < 0
        var head = String(value.magnitude)
        var tail = ""
        while head.count > 3 {
            let cut = head.index(head.endIndex, offsetBy: -3)
            tail = "," + String(head[cut...]) + tail
            head = String(head[..<cut])
        }
        return (isNegative ? "-" : "") + head + tail
    }
}
