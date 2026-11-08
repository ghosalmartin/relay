// swift-tools-version: 6.0
//
// LibGMKit: Swift bindings for libgm, the Google Messages web-client library from
// mautrix-gmessages. Self-contained and app-agnostic, so it can live in its own repo.
//
// Build the native library first: ./Bridge/build-xcframework.sh
import PackageDescription

let package = Package(
    name: "LibGMKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LibGMKit", targets: ["LibGMKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.39.0"),
    ],
    targets: [
        .binaryTarget(name: "GMBridgeC", path: "Bridge/build/GMBridge.xcframework"),
        .target(
            name: "LibGMKit",
            dependencies: ["GMBridgeC", .product(name: "SwiftProtobuf", package: "swift-protobuf")],
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .testTarget(name: "LibGMKitTests", dependencies: ["LibGMKit"]),
    ],
    swiftLanguageModes: [.v6]
)
