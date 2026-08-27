// swift-tools-version:5.9
import PackageDescription

// Module names are deliberately generic (MonitorCore, MonitorIO) so the product can be renamed
// by changing only the product names below and APP_NAME in scripts/config.sh.
let package = Package(
    name: "Candela",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Candela", targets: ["CandelaApp"]),
        .executable(name: "candelactl", targets: ["CandelaCLI"]),
        .library(name: "MonitorCore", targets: ["MonitorCore"]),
    ],
    targets: [
        // Pure logic: DDC/CI packets, MCCS tables, capability strings, EDID, brightness math.
        // No IOKit or AppKit, so everything here is unit tested.
        .target(name: "MonitorCore"),

        // Hardware access: IORegistry discovery, private IOAVService I2C, gamma tables.
        .target(
            name: "MonitorIO",
            dependencies: ["MonitorCore"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),

        // The menu bar app.
        .executableTarget(
            name: "CandelaApp",
            dependencies: ["MonitorCore", "MonitorIO"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        // Command line tool for diagnostics and scripting.
        .executableTarget(name: "CandelaCLI", dependencies: ["MonitorCore", "MonitorIO"]),

        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
    ]
)
