// swift-tools-version: 6.0
//
// LibGMKit: Swift bindings for libgm, the Google Messages web-client library from
// mautrix-gmessages. Self-contained and app-agnostic, so it can live in its own repo.
//
// Build the native library first: ./Bridge/build-xcframework.sh (macOS) or ./Bridge/build-linux.sh
import Foundation
import PackageDescription

let bridgeBuild = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Bridge/build")

#if os(Linux)
// Linux: the static library from Bridge/build-linux.sh, so CI can build and test without a Mac.
let nativeBridge: Target = .systemLibrary(name: "GMBridgeC", path: "Bridge/build/linux")
let nativeLinkerSettings: [LinkerSetting] = [.unsafeFlags(["-L", bridgeBuild.appendingPathComponent("linux").path])]
#else
// Apple platforms: the xcframework from Bridge/build-xcframework.sh.
let nativeBridge: Target = .binaryTarget(name: "GMBridgeC", path: "Bridge/build/GMBridge.xcframework")
let nativeLinkerSettings: [LinkerSetting] = [.linkedLibrary("resolv")]
#endif

let package = Package(
    name: "LibGMKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LibGMKit", targets: ["LibGMKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.39.0"),
    ],
    targets: [
        nativeBridge,
        .target(
            name: "LibGMKit",
            dependencies: ["GMBridgeC", .product(name: "SwiftProtobuf", package: "swift-protobuf")],
            linkerSettings: nativeLinkerSettings
        ),
        .testTarget(name: "LibGMKitTests", dependencies: ["LibGMKit"]),
    ],
    swiftLanguageModes: [.v6]
)
