// swift-tools-version: 6.0
// Package.swift is used for testing only. The app itself is built with build.sh.

import PackageDescription

let package = Package(
    name: "WorkMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "WorkMonitorLib",
            path: "Sources",
            exclude: ["main.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WorkMonitorTests",
            dependencies: ["WorkMonitorLib"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
