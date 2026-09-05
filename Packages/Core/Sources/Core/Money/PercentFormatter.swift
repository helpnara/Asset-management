import Foundation

/// 비중 표기. `0.44984…` → `"45.0"`
public enum PercentFormatter {

    /// 소수 첫째 자리까지. 1페이지의 `한국 29.8 / 미국 70.2` 표기다.
    ///
    /// `NSDecimalNumber(decimal:).intValue` 를 소수가 있는 값에 바로 부르면 안 된다.
    /// 반드시 `Decimals.roundedInt` 로 정수로 만든 뒤 변환한다 — 실제로 이 자리에서
    /// 비중이 통째로 `0.0` 으로 나오는 버그가 났다.
    public static func oneDecimal(_ fraction: Decimal) -> String {
        let tenths = Decimals.roundedInt(fraction * 1000, rounding: .plain)
        return "\(tenths / 10).\(abs(tenths % 10))"
    }
}
