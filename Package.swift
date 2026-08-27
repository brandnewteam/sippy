// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sippy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SippyCore", targets: ["SippyCore"]),
        .executable(name: "Sippy", targets: ["SippyApp"]),
        .executable(name: "sippy-spike", targets: ["sippy-spike"]),
    ],
    dependencies: [
        // Vendored copy of the official linphone SPM package (their GitLab was
        // unreachable at setup time; files mirrored from download.linphone.org).
        // The binary xcframeworks are still fetched from download.linphone.org
        // on first build. See Vendor/linphone-sdk-swift-macos/VERSION.
        .package(path: "Vendor/linphone-sdk-swift-macos")
    ],
    targets: [
        // Pure Swift, no SIP dependency: dial plan, models. Heavily unit-tested.
        .target(name: "SippyCore"),

        // The macOS app. Built as a plain executable by SwiftPM; `make app`
        // wraps it into Sippy.app with the frameworks and Info.plist.
        .executableTarget(
            name: "SippyApp",
            dependencies: [
                "SippyCore",
                .product(name: "linphonesw", package: "linphone-sdk-swift-macos"),
            ],
            swiftSettings: [
                // The generated linphone wrapper predates strict concurrency.
                .swiftLanguageMode(.v5)
            ]
        ),

        // M0 throwaway CLI to validate the SDK: codec list, registration, calls.
        .executableTarget(
            name: "sippy-spike",
            dependencies: [
                "SippyCore",
                .product(name: "linphonesw", package: "linphone-sdk-swift-macos"),
            ],
            swiftSettings: [
                // The generated linphone wrapper predates strict concurrency.
                .swiftLanguageMode(.v5)
            ]
        ),

        .testTarget(name: "SippyCoreTests", dependencies: ["SippyCore"]),
    ]
)
