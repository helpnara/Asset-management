import Foundation
import Testing
@testable import Core

/// **이 테스트가 없어서 앱이 안 켜졌다** (docs/08-feedback.md 159번).
///
/// 2026-09-19, 아이패드가 켤 때마다 죽었다. 차트 축 눈금으로 들어온 10¹⁹ 짜리
/// `Double` 을 `Int(raw)` 로 옮기다 트랩한 것이다. 심판이 없었다 — CI 스크린샷은
/// 체험 자료만 쓰므로 그런 값을 만들어 볼 일이 없고, 컴파일러는 실행 시점의
/// 범위를 모른다.
///
/// 그래서 **극단값을 여기서 눌러 둔다.** 기댓값은 파이썬으로 대조했다.
@Suite("SafeMath — 넘쳐도 죽지 않는 셈")
struct SafeMathTests {

    // MARK: - clampedInt

    @Test("평범한 값은 그대로 옮긴다")
    func ordinary() {
        #expect(SafeMath.clampedInt(0) == 0)
        #expect(SafeMath.clampedInt(1_234_567) == 1_234_567)
        #expect(SafeMath.clampedInt(-9_000) == -9_000)
    }

    @Test("소수점은 0 쪽으로 버린다")
    func truncatesTowardZero() {
        #expect(SafeMath.clampedInt(3.9) == 3)
        #expect(SafeMath.clampedInt(-3.9) == -3)
    }

    @Test("Int 를 넘으면 죽지 않고 끝값에서 멈춘다")
    func clampsOutOfRange() {
        // 이 값이 실제로 앱을 죽였다 (10¹⁹ > Int.max 9.22×10¹⁸).
        #expect(SafeMath.clampedInt(1e19) == Int.max)
        #expect(SafeMath.clampedInt(-1e19) == Int.min)
        #expect(SafeMath.clampedInt(1e30) == Int.max)
    }

    @Test("NaN · 무한대는 0 으로 둔다")
    func handlesNonFinite() {
        #expect(SafeMath.clampedInt(.nan) == 0)
        #expect(SafeMath.clampedInt(.infinity) == 0)
        #expect(SafeMath.clampedInt(-.infinity) == 0)
    }

    // MARK: - share

    @Test("비중은 평범한 값에서 정수 나눗셈 그대로다")
    func shareOrdinary() {
        // 3억 중 1억 → 10000bp 의 3333 (버림)
        #expect(SafeMath.share(100_000_000, times: 10_000, over: 300_000_000) == 3_333)
        #expect(SafeMath.share(50, times: 10_000, over: 100) == 5_000)
    }

    @Test("분모가 0 이면 0 이다 — 나눌 수 없는 것에 죽지 않는다")
    func shareByZero() {
        #expect(SafeMath.share(1_000, times: 10_000, over: 0) == 0)
    }

    @Test("중간 곱셈이 넘쳐도 답이 나온다")
    func shareOverflowsMidway() {
        // 1조 × 10,000 = 10¹⁶ 은 Int 안이지만, 여기에 더 큰 값을 넣으면
        // 곱셈이 먼저 넘친다. 그때도 비중은 그대로여야 한다.
        let huge = Int.max / 2
        #expect(SafeMath.share(huge, times: 10_000, over: huge) == 10_000)
        #expect(SafeMath.share(huge, times: 10_000, over: huge * 2) == 5_000)
    }

    @Test("음수 비중도 넘치지 않는다 — 부채가 그렇다")
    func shareNegative() {
        #expect(SafeMath.share(-100, times: 10_000, over: 400) == -2_500)
    }

    // MARK: - multiplyClamping

    @Test("만 · 억은 평범하게 곱한다")
    func multiplyOrdinary() {
        let limit = MoneyLimits.maxMinorUnits
        #expect(SafeMath.multiplyClamping(750, by: 10_000, limit: limit).result == 7_500_000)
        #expect(SafeMath.multiplyClamping(750, by: 10_000, limit: limit).hitLimit == false)
    }

    @Test("한도를 넘기면 한도에서 멈추고 그렇다고 말한다")
    func multiplyHitsLimit() {
        let limit = MoneyLimits.maxMinorUnits
        // 750 × 1억 = 750억은 아직 한도 안이다 (파이썬 대조).
        let under = SafeMath.multiplyClamping(750, by: 100_000_000, limit: limit)
        #expect(under.result == 75_000_000_000)
        #expect(under.hitLimit == false)
        // 75조가 되어야 한도에 닿는다.
        let hit = SafeMath.multiplyClamping(750_000, by: 100_000_000, limit: limit)
        #expect(hit.result == limit)
        #expect(hit.hitLimit)
    }

    @Test("곱셈이 Int 를 넘어도 죽지 않는다")
    func multiplyOverflows() {
        // 예전 코드는 가드보다 **먼저** 곱해서 여기서 트랩했다.
        let hit = SafeMath.multiplyClamping(Int.max / 2, by: 100_000_000,
                                            limit: MoneyLimits.maxMinorUnits)
        #expect(hit.result == MoneyLimits.maxMinorUnits)
        #expect(hit.hitLimit)
    }

    // MARK: - 한계

    @Test("한 칸의 한계는 1조 원 — 이 아래에서는 모든 셈이 Int 안에 있다")
    func limit() {
        #expect(MoneyLimits.maxMinorUnits == 999_999_999_999)
        #expect(MoneyLimits.isWithinRange(999_999_999_999))
        #expect(!MoneyLimits.isWithinRange(1_000_000_000_000))
        #expect(!MoneyLimits.isWithinRange(-1_000_000_000_000))
        // 한계 금액이 목표 금액(× 25)과 23년 복리(× 6 남짓)를 거쳐도
        // Int 안에 넉넉히 남는다 — 이것이 1조를 고른 이유다.
        #expect(MoneyLimits.maxMinorUnits * 25 < Int.max / 1_000)
    }
}
