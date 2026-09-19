import Foundation

/// **넘쳐도 죽지 않아야 하는 자리**를 위한 셈 (docs/08-feedback.md 159번).
///
/// 이 앱의 금액 계산은 넘치면 **즉시 실패**한다 — `Money` 도 `Decimals.roundedInt`
/// 도 그렇게 짜여 있고, 그것은 옳다. 금액 앱에서 조용히 잘린 숫자를 보여 주는
/// 것보다 멈추는 편이 낫기 때문이다 (ADR-0003).
///
/// 그런데 **그 규칙이 맞지 않는 자리가 둘** 있다.
///
/// **① 화면이 그리기만 하는 값.** 차트 축 눈금은 우리가 만든 것이 아니라
/// 그리기 라이브러리가 도메인에서 뽑아 건네주는 `Double` 이다. 그 값이 `Int`
/// 범위를 넘으면 `Int(raw)` 가 그 자리에서 앱을 죽인다 — 2026-09-19 에 실제로
/// 그렇게 됐고, **현황판이 첫 화면이라 값을 고칠 기회조차 없었다.** 자료가
/// 이상하면 이상한 그림을 보여 줘야지, 앱이 안 켜지면 안 된다.
///
/// **② 비중을 낼 때의 중간 곱셈.** `값 × 10,000 ÷ 합계` 는 결과가 작아도
/// **중간값이 넘친다.** 나누기 전에 곱하기 때문이다.
public enum SafeMath {

    /// `Double` 을 `Int` 로. **범위를 벗어나면 죽지 않고 끝값으로 자른다.**
    ///
    /// `Int(someDouble)` 은 범위를 벗어나면 트랩이다. 그리기용 값에는 그 규칙을
    /// 적용하지 않는다 — 10¹⁹ 짜리 눈금은 "이상한 눈금" 이지 "멈출 일" 이 아니다.
    /// `NaN` · `무한대` 도 여기서 걸러 0 으로 둔다.
    public static func clampedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let truncated = value.rounded(.towardZero)
        if let exact = Int(exactly: truncated) { return exact }
        return truncated > 0 ? Int.max : Int.min
    }

    /// `value × numerator ÷ denominator` — **중간 곱셈이 넘치지 않는다.**
    ///
    /// 비중을 낼 때 쓴다. 정수로만 세는 규칙(ADR-0003)을 지키면서, 넘칠 때만
    /// `Decimal` 로 돌아간다 — 느리지만 그 길로 오는 일 자체가 드물다.
    /// 분모가 0 이면 0 이다. 나눌 수 없는 것을 나누려다 죽지 않는다.
    public static func share(_ value: Int, times numerator: Int, over denominator: Int) -> Int {
        guard denominator != 0 else { return 0 }
        let (product, overflowed) = value.multipliedReportingOverflow(by: numerator)
        if !overflowed { return product / denominator }
        // 넘친 길. **`Double` 을 거치지 않는다** — 15자리를 넘으면 그쪽이 또
        // 틀린 답을 낸다. 부호를 뽑고 절댓값으로 내림하면 정수 나눗셈(0 쪽으로
        // 버림)과 같은 답이 된다.
        let negative = ((value < 0) != (numerator < 0)) != (denominator < 0)
        let magnitude = Decimal(value.magnitude) * Decimal(numerator.magnitude)
            / Decimal(denominator.magnitude)
        var floored = Decimal()
        var input = magnitude
        NSDecimalRound(&floored, &input, 0, .down)
        guard floored <= Decimal(Int.max) else { return negative ? Int.min : Int.max }
        let whole = NSDecimalNumber(decimal: floored).intValue
        return negative ? -whole : whole
    }

    /// `value × factor` — **넘치면 한도에서 멈춘다.** `만` · `억` 버튼이 쓴다.
    ///
    /// 한도를 넘겼는지도 함께 돌려준다. 눌러도 아무 일이 안 일어나는 것과
    /// "여기까지만 올렸습니다" 는 사용자에게 전혀 다른 일이다 (156번).
    public static func multiplyClamping(_ value: Int, by factor: Int,
                                        limit: Int) -> (result: Int, hitLimit: Bool) {
        let (product, overflowed) = value.multipliedReportingOverflow(by: factor)
        if overflowed || product > limit { return (limit, true) }
        if product < -limit { return (-limit, true) }
        return (product, false)
    }
}

/// 이 앱이 한 칸에 담을 수 있는 금액의 한계.
///
/// **1조 원.** 예전에는 1,000조(10¹⁵)였는데, 그 값이 목표 금액(×25)과 23년
/// 복리를 거치면 10¹⁹ 를 넘어 `Int` 밖으로 나간다. 그리고 `만` · `억` 버튼을
/// 몇 번 누르는 것만으로 **정상 입력으로** 거기에 닿았다 (159번).
///
/// 우리 가족 노후자금에 한 칸 1조가 필요할 일은 없다. 한계를 현실에 맞추면
/// 그 아래의 모든 셈이 `Int` 안에서 끝난다.
public enum MoneyLimits {
    /// 한 칸에 넣을 수 있는 최대 금액 (원).
    public static let maxMinorUnits = 999_999_999_999

    /// 궤적을 굴려도 되는 입력인가. 하나라도 한계를 넘으면 굴리지 않는다.
    public static func isWithinRange(_ minorUnits: Int) -> Bool {
        minorUnits >= -maxMinorUnits && minorUnits <= maxMinorUnits
    }
}
