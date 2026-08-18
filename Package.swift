// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Candela",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MonitorCore", targets: ["MonitorCore"]),
    ],
    targets: [
        // Pure logic: DDC/CI packets, MCCS tables, capability strings, EDID, brightness math.
        // No IOKit or AppKit, so everything here is unit tested.
        .target(name: "MonitorCore"),
    ]
)
