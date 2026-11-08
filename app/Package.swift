// swift-tools-version: 6.0
//
// Layers, innermost first. The compiler enforces that dependencies only point inwards:
//
//   MessagingDomain        entities + ports. No dependencies.
//   MessagingApplication   use cases. Depends on the domain only.
//   Presentation           MVI view models. Depends on use cases, not on SwiftUI.
//   LibGMAdapter           the only code that knows libgm exists. Implements MessagingClient.
//   KeychainAdapter        implements SessionStore.
//
// The app target (see project.yml) holds the SwiftUI views and the composition root.
import PackageDescription

// Layers that build anywhere (and are tested on Linux CI as well as macOS).
var targets: [Target] = [
    .target(name: "AsyncBroadcast"),
    .target(name: "MessagingDomain"),
    .target(name: "MessagingApplication", dependencies: ["MessagingDomain"]),
    .target(name: "Presentation", dependencies: ["MessagingApplication", "MessagingDomain"]),

    .target(name: "MessagingTestSupport", dependencies: ["MessagingDomain", "AsyncBroadcast"], path: "Tests/MessagingTestSupport"),
    .testTarget(name: "AsyncBroadcastTests", dependencies: ["AsyncBroadcast"]),
    .testTarget(name: "MessagingApplicationTests", dependencies: ["MessagingApplication", "MessagingTestSupport"]),
    .testTarget(name: "PresentationTests", dependencies: ["Presentation", "MessagingApplication", "MessagingTestSupport"]),
]
var products: [Product] = [
    .library(name: "MessagingDomain", targets: ["MessagingDomain"]),
    .library(name: "MessagingApplication", targets: ["MessagingApplication"]),
    .library(name: "Presentation", targets: ["Presentation"]),
]
var dependencies: [Package.Dependency] = []

// Adapters need the Mac: the Go bridge ships as an xcframework and the Keychain is Apple-only.
#if os(macOS)
dependencies.append(.package(url: "https://github.com/apple/swift-protobuf", from: "1.28.0"))
targets += [
    .binaryTarget(name: "GMBridgeC", path: "../bridge/build/GMBridge.xcframework"),
    .target(
        name: "LibGMAdapter",
        dependencies: [
            "MessagingDomain",
            "AsyncBroadcast",
            "GMBridgeC",
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        ]
    ),
    .target(name: "KeychainAdapter", dependencies: ["MessagingDomain"]),
    .testTarget(name: "LibGMAdapterTests", dependencies: ["LibGMAdapter"]),
]
products += [
    .library(name: "LibGMAdapter", targets: ["LibGMAdapter"]),
    .library(name: "KeychainAdapter", targets: ["KeychainAdapter"]),
]
#endif

let package = Package(
    name: "Relay",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v6]
)
