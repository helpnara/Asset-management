import Foundation

/// **5년치 자료로 화면 시간 재기** (docs/18-stage5-foundation.md 5-7 · R9).
///
/// 실행 인자 `-seedLargeSample` 이 있을 때만 켜진다 — 그때 체험 저장소(인메모리)에 12주가
/// 아니라 260주(5년)를 채우고, 화면이 처음 뜨기까지 걸린 시간을 표준 출력에 찍는다.
/// 결과는 CI 로그에만 남는다. 사용자 폰에서는 인자가 없으니 아무것도 안 한다.
enum LaunchTiming {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-seedLargeSample")

    /// 앱이 뜬 시각. `SlowRichApp.init` 이 맨 먼저 건드려 그때로 정해진다.
    static let start = Date()

    /// 체험 자료로 채울 주 수.
    static var sampleWeeks: Int { isOn ? 260 : 12 }

    static func mark(_ label: String) {
        guard isOn else { return }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("⏱ \(label): \(ms) ms")
    }
}
