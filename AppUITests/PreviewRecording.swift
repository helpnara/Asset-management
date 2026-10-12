import UIKit
import XCTest

/// **App Store 미리 보기 녹화** (Tools/preview, 2026-10-12).
///
/// 애플 규정(2.3.4)상 미리 보기는 **앱 화면을 녹화한 것만** 쓸 수 있다. 그래서 체험 자료(가상의 가족)로
/// 앱을 띄워 실제로 눌러 가며 장면 다섯을 만든다. CI(`preview.yml`)가 그동안 시뮬레이터를 녹화하고,
/// 여기서 찍는 `PREVIEW-MARK` 표시(장면 이름 · 시작/끝 · 시각)로 녹화를 잘라 붙인다.
///
/// 앱 동작을 시험하는 테스트가 아니다 — 앱 CI 스킴(`SlowRich`)에는 안 들어가고 `SlowRichPreview` 스킴에만 있다.
@MainActor
final class PreviewRecording: XCTestCase {

    private func mark(_ scene: String, _ edge: String) {
        let line = "PREVIEW-MARK \(scene) \(edge) \(String(format: "%.3f", Date().timeIntervalSince1970))"
        print(line)
        NSLog("%@", line)
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    /// 앱이 **앞으로 나온 뒤에** 돌려준다. 첫 녹화에서 점검 완료 장면에 홈 화면이 찍혔다 —
    /// 앱이 뜨기 전에 표시를 찍었다.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-seedSampleData"] + arguments
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 8) { app.activate() }
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    /// 사람 손처럼 천천히 끈다. `velocity` 는 초당 포인트.
    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector, velocity: CGFloat = 260) {
        let start = app.coordinate(withNormalizedOffset: from)
        let end = app.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: 0.25)
    }

    /// 한 번에 친다. 한 글자씩 치면 CI 에서 장면이 37초로 늘었고, 치는 도중의 반쪽 숫자에
    /// "30% 넘게 움직였습니다" 표시가 번쩍였다 (첫 녹화).
    private func type(_ app: XCUIApplication, _ text: String) {
        app.typeText(text)
    }

    func testRecordPreview() throws {
        continueAfterFailure = true

        // 1. 주간 점검 — 종목 평가액을 적으면 지난주 대비 증감이 바로 (첫 칸에 저절로 커서가 간다)
        // 사람처럼 현황판의 `지금 입력` 을 눌러 연다. `-startReview` 로 바로 열면 아이패드에서 점검 창이
        // 열렸다 닫혔다를 되풀이해 칸을 누를 수 없었다 (아이패드 세 번째 녹화).
        var app = launch(["-startTab", "dashboard"])
        pause(1.5)
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["지금 입력", "다시 열기"])).firstMatch
        if open.waitForExistence(timeout: 5) { open.tap() }
        pause(1.5)
        mark("review", "start")
        pause(0.8)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // **아이패드는 치지 않고 보여만 준다.** 칸을 누르자 점검 창이 15초쯤 뒤 저절로 닫혀(아이패드 네 번째
            // 녹화) 뒤 장면을 하나도 못 찍었다. 첫 칸에는 이미 커서가 가 있다.
            pause(4.0)
        } else {
            type(app, "48650000")
            pause(1.0)
            let next = app.buttons["다음"]
            if next.waitForExistence(timeout: 2) { next.tap() }
            pause(0.8)
            type(app, "26510000")
            pause(1.5)
        }
        mark("review", "end")
        app.terminate()

        // 2. 점검 완료 — 연속 기록 · 축하
        app = launch(["-startTab", "dashboard", "-showReviewComplete"])
        pause(1.5)
        mark("complete", "start")
        pause(4.5)
        mark("complete", "end")
        app.terminate()

        // 3. 현황판 — 궤적과 로드맵이 보이게 천천히 내린다
        app = launch(["-startTab", "dashboard"])
        pause(2.0)
        mark("dashboard", "start")
        pause(1.2)
        drag(app, from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.38))
        pause(1.2)
        drag(app, from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.42))
        pause(1.5)
        mark("dashboard", "end")
        app.terminate()

        // 4. 시뮬레이션 — 손잡이를 돌리면 그래프가 따라온다
        app = launch(["-startTab", "simulation"])
        pause(2.5)
        mark("simulation", "start")
        pause(1.0)
        let slider = app.sliders.firstMatch
        if slider.waitForExistence(timeout: 3) {
            if !slider.isHittable {
                drag(app, from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.45))
                pause(0.6)
            }
            let position = slider.normalizedSliderPosition
            let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5))
            let right = slider.coordinate(withNormalizedOffset: CGVector(dx: min(position + 0.35, 0.95), dy: 0.5))
            thumb.press(forDuration: 0.1, thenDragTo: right,
                        withVelocity: XCUIGestureVelocity(rawValue: 120), thenHoldForDuration: 0.8)
            pause(0.8)
            let back = slider.coordinate(withNormalizedOffset: CGVector(dx: min(position + 0.35, 0.95), dy: 0.5))
            let left = slider.coordinate(withNormalizedOffset: CGVector(dx: max(position - 0.1, 0.05), dy: 0.5))
            back.press(forDuration: 0.1, thenDragTo: left,
                       withVelocity: XCUIGestureVelocity(rawValue: 120), thenHoldForDuration: 0.8)
        }
        pause(1.2)
        mark("simulation", "end")
        app.terminate()

        // 5. 자산 진단 — 원칙들이 한 화면에
        app = launch(["-startTab", "more", "-startDiagnostics"])
        pause(2.0)
        mark("diagnostics", "start")
        pause(1.5)
        drag(app, from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.4))
        pause(2.0)
        mark("diagnostics", "end")
        app.terminate()
    }
}
