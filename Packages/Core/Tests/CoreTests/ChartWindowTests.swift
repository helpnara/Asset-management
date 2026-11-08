import Foundation
import Testing
@testable import Core

/// **크게 보기의 확대 · 넘기기 셈** (docs/08-feedback.md 215번). 기댓값은 같은 셈을 파이썬으로
/// 따로 짜서 대조했다(테두리 0~1000).
@Suite("ChartWindow — 두 손가락 확대 · 끌어 넘기기")
struct ChartWindowTests {

    typealias Span = ChartWindow.Span
    let bounds = Span(lower: 0, upper: 1000)

    @Test("벌리면 좁아지고, 손가락 밑 자리는 그대로 남는다")
    func zoomKeepsAnchor() {
        #expect(ChartWindow.zoomed(bounds, by: 2, anchor: 0.5, bounds: bounds, minLength: 50)
                == Span(lower: 250, upper: 750))
        #expect(ChartWindow.zoomed(bounds, by: 2, anchor: 0.25, bounds: bounds, minLength: 50)
                == Span(lower: 125, upper: 625))
    }

    @Test("아무리 벌려도 최소 길이까지만")
    func zoomStopsAtMinimum() {
        #expect(ChartWindow.zoomed(Span(lower: 400, upper: 600), by: 10, anchor: 0.5, bounds: bounds, minLength: 50)
                == Span(lower: 475, upper: 525))
    }

    @Test("오므리면 넓어지되 테두리 안으로 밀려 들어온다")
    func zoomOutStaysInside() {
        #expect(ChartWindow.zoomed(Span(lower: 800, upper: 1000), by: 0.5, anchor: 0.5, bounds: bounds, minLength: 50)
                == Span(lower: 600, upper: 1000))
        #expect(ChartWindow.zoomed(Span(lower: 850, upper: 950), by: 0.5, anchor: 0.9, bounds: bounds, minLength: 50)
                == Span(lower: 760, upper: 960))
        // 테두리보다 넓어질 수는 없다.
        #expect(ChartWindow.zoomed(Span(lower: 400, upper: 600), by: 0.01, anchor: 0.5, bounds: bounds, minLength: 50)
                == bounds)
    }

    @Test("넘기기는 길이를 지키고 테두리에서 멈춘다")
    func panStopsAtEdges() {
        let window = Span(lower: 200, upper: 400)
        #expect(ChartWindow.panned(window, by: 150, bounds: bounds) == Span(lower: 350, upper: 550))
        #expect(ChartWindow.panned(window, by: -500, bounds: bounds) == Span(lower: 0, upper: 200))
        #expect(ChartWindow.panned(Span(lower: 800, upper: 1000), by: 100, bounds: bounds)
                == Span(lower: 800, upper: 1000))
    }

    @Test("손가락을 오른쪽으로 끌면 과거 쪽으로 — 화면 폭에 비례")
    func panDeltaFollowsFinger() {
        #expect(ChartWindow.panDelta(points: 90, width: 360, window: Span(lower: 200, upper: 400)) == -50)
        #expect(ChartWindow.panDelta(points: 90, width: 0, window: bounds) == 0)
    }

    @Test("테두리로 들이기 — 넘치면 테두리 그대로")
    func clampKeepsLength() {
        #expect(ChartWindow.clamp(Span(lower: -50, upper: 150), to: bounds) == Span(lower: 0, upper: 200))
        #expect(ChartWindow.clamp(Span(lower: -50, upper: 1200), to: bounds) == bounds)
    }

    @Test("주간 점이 4pt 보다 붙으면 선만 — 10년 폭은 선만, 반년 폭은 점")
    func marksNeedRoom() {
        // 7일 / 3650일 × 360pt ≈ 0.69pt · 7일 / 182일 × 360pt ≈ 13.8pt
        #expect(!ChartWindow.showsMarks(step: 7, window: Span(lower: 0, upper: 3650), width: 360))
        #expect(ChartWindow.showsMarks(step: 7, window: Span(lower: 0, upper: 182), width: 360))
    }

    @Test("짧은 창의 눈금은 1 · 2 · 3 · 6 달 간격")
    func monthStride() {
        #expect(ChartWindow.monthStride(months: 3) == 1)
        #expect(ChartWindow.monthStride(months: 5) == 2)
        #expect(ChartWindow.monthStride(months: 8) == 2)
        #expect(ChartWindow.monthStride(months: 12) == 3)
        #expect(ChartWindow.monthStride(months: 23) == 6)
    }

    @Test("망가진 손짓 값은 창을 그대로 둔다")
    func ignoresBrokenInput() {
        let window = Span(lower: 200, upper: 400)
        #expect(ChartWindow.zoomed(window, by: .nan, anchor: 0.5, bounds: bounds, minLength: 50) == window)
        #expect(ChartWindow.zoomed(window, by: 0, anchor: 0.5, bounds: bounds, minLength: 50) == window)
        #expect(ChartWindow.panned(window, by: .infinity, bounds: bounds) == window)
    }
}
