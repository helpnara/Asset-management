import Foundation

/// **차트의 보이는 구간** — 두 손가락으로 넓히고 좁히기 · 끌어 넘기기 (docs/08-feedback.md 215번).
///
/// 2026-11-08 사용자: *"순자산 궤적 확대 시 두 손가락으로 자세히 볼 수 있는 기능(마치 주식 차트처럼),
/// 확대된 상태에서 좌우로 이동하면서 스크롤이 되는 기능"*. 크게 보기는 기간(1년 · 5년 · 은퇴까지 · 전체)
/// 하나를 한 화면 폭에 넣어서, 주마다 찍는 실제 기록 점이 5년 창부터 한 덩어리로 포갰다.
///
/// 화면은 이 셈의 결과(보이는 구간)를 차트의 x 범위로 쓴다. 셈만 여기 두어 원격 세션에서도 시험으로 누른다.
/// 값은 기준 시각부터의 **초**다 — 날짜를 그대로 다루면 시험이 달력에 묶인다. 금액이 아니므로 `Double` 을 쓴다.
public enum ChartWindow {

    /// 닫힌 구간. `lower <= upper` 를 늘 지킨다.
    public struct Span: Equatable, Sendable {
        public let lower: Double
        public let upper: Double
        public var length: Double { upper - lower }

        public init(lower: Double, upper: Double) {
            self.lower = min(lower, upper)
            self.upper = max(lower, upper)
        }
    }

    /// 창을 바깥 테두리 안으로 들인다. 길이는 지키고(테두리보다 길면 테두리 그대로) 자리만 옮긴다.
    public static func clamp(_ window: Span, to bounds: Span) -> Span {
        guard window.length < bounds.length else { return bounds }
        if window.lower < bounds.lower {
            return Span(lower: bounds.lower, upper: bounds.lower + window.length)
        }
        if window.upper > bounds.upper {
            return Span(lower: bounds.upper - window.length, upper: bounds.upper)
        }
        return window
    }

    /// **두 손가락으로 넓히고 좁히기.** `scale` 은 손가락 사이가 몇 배가 됐나(벌리면 1 보다 크다 → 좁아진다).
    /// `anchor` 는 손가락 가운데가 창의 어디쯤인가(0 왼쪽 끝 · 1 오른쪽 끝) — 그 자리가 손가락 밑에 그대로 남는다.
    /// 길이는 `minLength` 와 테두리 길이 사이로 묶는다.
    public static func zoomed(_ window: Span, by scale: Double, anchor: Double,
                              bounds: Span, minLength: Double) -> Span {
        guard scale.isFinite, scale > 0, anchor.isFinite else { return clamp(window, to: bounds) }
        let fraction = Swift.min(Swift.max(anchor, 0), 1)
        let floor = Swift.min(minLength, bounds.length)
        let length = Swift.min(Swift.max(window.length / scale, floor), bounds.length)
        let pivot = window.lower + window.length * fraction
        let lower = pivot - length * fraction
        return clamp(Span(lower: lower, upper: lower + length), to: bounds)
    }

    /// **끌어 넘기기.** `delta` 만큼 옮긴다(양수면 미래 쪽). 테두리 밖으로는 안 나간다.
    public static func panned(_ window: Span, by delta: Double, bounds: Span) -> Span {
        guard delta.isFinite else { return clamp(window, to: bounds) }
        return clamp(Span(lower: window.lower + delta, upper: window.upper + delta), to: bounds)
    }

    /// 손가락이 화면에서 `points` 만큼 움직였을 때 창이 옮겨 갈 양. 손가락을 오른쪽으로 끌면
    /// 그림이 따라 오른쪽으로 가므로 **과거 쪽**(음수)으로 넘어간다 — 지도를 끄는 것과 같다.
    public static func panDelta(points: Double, width: Double, window: Span) -> Double {
        guard width > 0, points.isFinite else { return 0 }
        return -points / width * window.length
    }

    /// **점을 찍을 만큼 성긴가.** 점 사이(`step` 초)가 화면에서 `minSpacing` 포인트보다 좁으면
    /// 점이 한 덩어리로 포개진다 — 그때는 선만 그린다. 확대하면 다시 넓어져 점이 돌아온다.
    public static func showsMarks(step: Double, window: Span, width: Double, minSpacing: Double = 4) -> Bool {
        guard window.length > 0, width > 0, step > 0 else { return true }
        return step / window.length * width >= minSpacing
    }

    /// 짧은 창의 눈금 간격(달). 눈금이 다섯 개 안팎이 되도록 1 · 2 · 3 · 6 달 중에서 고른다.
    public static func monthStride(months: Int) -> Int {
        switch months {
        case ..<6: return 1
        case ..<11: return 2
        case ..<16: return 3
        default: return 6
        }
    }
}
