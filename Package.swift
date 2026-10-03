// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .swiftLanguageMode(.v6),
]

let package: Package = .init(
    name: "Zip",
    products: [
        .library(name: "Zip", targets: ["Zip"]),
    ],
    targets: [
        .target(
            name: "Minizip",
            dependencies: [],
            path: "Zip/minizip",
            exclude: ["module"],
            linkerSettings: [
                .linkedLibrary("z"),
            ],
        ),
        .target(
            name: "Zip",
            dependencies: ["Minizip"],
            path: "Zip",
            exclude: ["minizip", "zlib"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "ZipTests",
            dependencies: ["Zip"],
            path: "ZipTests",
            swiftSettings: swiftSettings,
        ),
    ],
)
