// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        // 순수 Swift. Foundation 외 의존이 없어야 한다 (ADR-0002).
        // SwiftUI / SwiftData를 import하지 않으므로 시뮬레이터 없이 초 단위로 테스트된다.
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
