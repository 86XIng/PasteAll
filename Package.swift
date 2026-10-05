// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PasteAll",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PasteAllCore", targets: ["PasteAllCore"]),
        .executable(name: "PasteAll", targets: ["PasteAll"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/jmcnamara/libxlsxwriter.git", from: "1.2.4")
    ],
    targets: [
        .target(
            name: "PasteAllCore",
            dependencies: [
                "SwiftSoup",
                .product(name: "libxlsxwriter", package: "libxlsxwriter")
            ]
        ),
        .executableTarget(
            name: "PasteAll",
            dependencies: ["PasteAllCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PasteAllCoreTests",
            dependencies: ["PasteAllCore"]
        ),
        .testTarget(
            name: "PasteAllTests",
            dependencies: ["PasteAll"]
        )
    ]
)
