// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WasiiBuds",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WasiiBuds",
            targets: ["WasiiBuds"]
        ),
        .library(name: "WasiiBudsWidget", targets: ["WasiiBudsWidget"]),
    ],
    targets: [
        .target(name: "BudsDomain"),
        .target(name: "BudsStorage", dependencies: ["BudsDomain"]),
        .target(name: "BudsWidgetData"),
        .target(
            name: "WasiiBuds",
            dependencies: ["BudsDomain", "BudsStorage", "BudsWidgetData"],
            resources: [.process("Resources")]
        ),
        .target(name: "WasiiBudsWidget", dependencies: ["BudsWidgetData"]),
        .testTarget(name: "BudsDomainTests", dependencies: ["BudsDomain"]),
        .testTarget(name: "BudsStorageTests", dependencies: ["BudsStorage", "BudsDomain"]),
        .testTarget(name: "BudsWidgetDataTests", dependencies: ["BudsWidgetData"]),
    ]
)
