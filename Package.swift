// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Inertia",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Inertia",
            targets: ["Inertia"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Inertia",
            resources: [
                .copy("Metal/")
            ],
            swiftSettings: [SwiftSetting.define("INERTIA_EDITOR_RUNTIME")]),
        .testTarget(
            name: "InertiaTests",
            dependencies: ["Inertia"]),
    ]
)
