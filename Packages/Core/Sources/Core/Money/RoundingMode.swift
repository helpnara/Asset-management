import Foundation

/// 금액·수량을 정수로 내릴 때의 반올림 정책.
///
/// 앱 전체에서 반올림이 일어나는 지점은 이 파일 하나로 모은다.
/// 기본값은 `.bankers` — 반복 계산에서 한쪽으로 치우치지 않는다.
public enum RoundingMode: Sendable, Hashable {
    case bankers
    case up
    case down
    case plain

    var foundationMode: NSDecimalNumber.RoundingMode {
        switch self {
        case .bankers: return .bankers
        case .up: return .up
        case .down: return .down
        case .plain: return .plain
        }
    }
}

enum Decimals {
    static func rounded(_ value: Decimal, scale: Int, mode: RoundingMode) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode.foundationMode)
        return result
    }

    /// 소수를 정수로 내린다. Int 범위를 벗어나면 조용히 자르지 않고 즉시 실패한다.
    static func roundedInt(_ value: Decimal, rounding: RoundingMode) -> Int {
        let result = rounded(value, scale: 0, mode: rounding)
        precondition(
            result <= Decimal(Int.max) && result >= Decimal(Int.min),
            "값이 Int 범위를 벗어났습니다: \(value)"
        )
        return NSDecimalNumber(decimal: result).intValue
    }

    /// 10^exponent
    static func powerOfTen(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }

    /// `Double` 을 소수 12자리로 고정해 `Decimal` 로 옮긴다.
    ///
    /// `Decimal(someDouble)` 은 2진 부동소수의 잡음을 그대로 들고 온다.
    /// 수익률처럼 Double 로 계산할 수밖에 없는 값(12제곱근 등)을 금액 계산에
    /// 들이기 전 이 문을 통과시킨다.
    static func fromDouble(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.12f", value)) ?? Decimal(0)
    }
}
