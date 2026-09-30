// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PaymentsLk",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "PaymentsLk", targets: ["PaymentsLk"]),
    ],
    targets: [
        .target(
            name: "PaymentsLk",
            path: "Sources/PaymentsLk"
        ),
        .testTarget(
            name: "PaymentsLkTests",
            dependencies: ["PaymentsLk"],
            path: "Tests/PaymentsLkTests"
        ),
    ]
)
