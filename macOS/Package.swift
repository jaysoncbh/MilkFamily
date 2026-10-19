// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Naijia",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Naijia", targets: ["NaijiaApp"])],
    targets: [
        .target(name: "NaijiaCore", path: "01_源码/NaijiaCore"),
        .executableTarget(name: "NaijiaApp", dependencies: ["NaijiaCore"], path: "01_源码/NaijiaApp"),
        .executableTarget(name: "NaijiaChecks", dependencies: ["NaijiaCore"], path: "Tests/NaijiaCoreTests"),
        .executableTarget(name: "NaijiaUsageChecks", dependencies: ["NaijiaCore"], path: "Tests/UsageChecks"),
        .executableTarget(name: "NaijiaResilienceChecks", dependencies: ["NaijiaCore"], path: "Tests/ResilienceChecks"),
        .executableTarget(name: "NaijiaUsageHistoryChecks", dependencies: ["NaijiaCore"], path: "Tests/UsageHistoryChecks")
    ]
)
