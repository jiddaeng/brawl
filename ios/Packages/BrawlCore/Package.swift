// swift-tools-version:5.9
// BrawlCore: Apple 프레임워크 없이 Foundation 만 쓰는 로직 (Linux 에서도 빌드·테스트 가능)
// BrawlEngine: JavaScriptCore·CoreGraphics 로 engine/draft-engine.js 를 실행하는 브리지 (Apple 플랫폼 전용)
import PackageDescription

let package = Package(
    name: "BrawlCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BrawlCore", targets: ["BrawlCore"]),
        .library(name: "BrawlEngine", targets: ["BrawlEngine"]),
    ],
    targets: [
        .target(name: "BrawlCore"),
        .target(name: "BrawlEngine", dependencies: ["BrawlCore"]),
        .testTarget(name: "BrawlCoreTests", dependencies: ["BrawlCore"]),
        .testTarget(name: "BrawlEngineTests", dependencies: ["BrawlEngine", "BrawlCore"]),
    ]
)
