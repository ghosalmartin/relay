// swift-tools-version: 6.0
//
// Layers, innermost first. The compiler enforces that dependencies only point inwards:
//
//   MessagingDomain        entities + ports. No dependencies.
//   MessagingApplication   use cases. Depends on the domain only.
//   Presentation           MVI view models. Depends on use cases, not on SwiftUI.
//   LibGMAdapter           the only code that knows libgm exists. Implements MessagingClient
//                          on top of LibGMKit (../LibGMKit, a standalone package).
//   KeychainAdapter        implements SessionStore.
//
// The app target (see project.yml) holds the SwiftUI views and the composition root.
import PackageDescription

// Everything except the Keychain builds and tests on Linux as well as macOS.
var targets: [Target] = [
    .target(name: "AsyncBroadcast"),
    .target(name: "MessagingDomain"),
    .target(name: "MessagingApplication", dependencies: ["MessagingDomain"]),
    .target(name: "Presentation", dependencies: ["MessagingApplication", "MessagingDomain"]),
    .target(name: "LibGMAdapter", dependencies: ["MessagingDomain", "AsyncBroadcast", "LibGMKit"]),

    .target(name: "MessagingTestSupport", dependencies: ["MessagingDomain", "AsyncBroadcast"], path: "Tests/MessagingTestSupport"),
    .testTarget(name: "AsyncBroadcastTests", dependencies: ["AsyncBroadcast"]),
    .testTarget(name: "MessagingApplicationTests", dependencies: ["MessagingApplication", "MessagingTestSupport"]),
    .testTarget(name: "PresentationTests", dependencies: ["Presentation", "MessagingApplication", "MessagingTestSupport"]),
    .testTarget(name: "LibGMAdapterTests", dependencies: ["LibGMAdapter", "LibGMKit", "MessagingTestSupport"]),
]
var products: [Product] = [
    .library(name: "MessagingDomain", targets: ["MessagingDomain"]),
    .library(name: "MessagingApplication", targets: ["MessagingApplication"]),
    .library(name: "Presentation", targets: ["Presentation"]),
    .library(name: "LibGMAdapter", targets: ["LibGMAdapter"]),
    .library(name: "MessagingTestSupport", targets: ["MessagingTestSupport"]),
]

// The Keychain is Apple-only.
#if canImport(Security)
targets += [
    .target(name: "KeychainAdapter", dependencies: ["MessagingDomain"]),
    .testTarget(name: "KeychainAdapterTests", dependencies: ["KeychainAdapter", "MessagingDomain"]),
]
products.append(.library(name: "KeychainAdapter", targets: ["KeychainAdapter"]))
#endif

let package = Package(
    name: "Relay",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: [
        // Local today; swap for a URL once LibGMKit moves to its own repo.
        .package(name: "LibGMKit", path: "../LibGMKit"),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
