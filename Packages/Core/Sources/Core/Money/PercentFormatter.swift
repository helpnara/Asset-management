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

    /// 정수 퍼센트. **비중은 전부 이쪽을 쓴다** (docs/08-feedback.md 18번).
    ///
    /// 소수 첫째 자리까지 적었더니 화면이 산만했다. 비중은 어림으로 읽는
    /// 숫자라 `31.7%` 와 `32%` 가 알려 주는 것이 같다.
    ///
    /// ⚠️ **한 줄씩 따로 반올림하면 합이 100이 안 된다.** 여러 줄을 함께
    /// 보여줄 때는 `Allocation.Slice.actualPercent` 를 쓰라 — 그쪽은
    /// 최대잔여법으로 합을 100 에 맞춰 둔다.
    public static func integer(_ fraction: Decimal) -> String {
        "\(Decimals.roundedInt(fraction * 100, rounding: .plain))"
    }
}
