// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Needle",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Needle", targets: ["Needle"]),
    ],
    targets: [
        // Prebuilt by Scripts/update-needle.sh; arm64 only, like the app.
        .binaryTarget(name: "CNeedle", path: "CNeedle.xcframework"),
        .target(
            name: "Needle",
            dependencies: ["CNeedle"],
            // The engine is C++ behind a C API; binary targets can't carry
            // linker settings, so the wrapper pulls in libc++ for it.
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .testTarget(name: "NeedleTests", dependencies: ["Needle"]),
    ]
)
