// swift-tools-version: 5.9
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let arch = ProcessInfo.processInfo.environment["BATTUNE_ARCH"] ?? "arm64"
let configuration = ProcessInfo.processInfo.environment["BATTUNE_CONFIGURATION"] ?? "debug"
let package = Package(
    name: "Battune", defaultLocalization: "en", platforms: [.macOS(.v13)],
    products: [.executable(name: "Battune", targets: ["Battune"]), .executable(name: "BattuneHelper", targets: ["BattuneHelper"])],
    targets: [
        .systemLibrary(name: "CBattuneCore", path: "shared/FFI"),
        .target(name: "BattuneDomain", dependencies: ["CBattuneCore"], path: "app/Battune", exclude: ["Services", "Views", "App", "Localization"], sources: ["Models", "Persistence", "Statistics", "Scheduling"], linkerSettings: [.unsafeFlags(["-L\(root)/build/rust/\(arch)/\(configuration)"]), .linkedLibrary("battune_core")]),
        .target(name: "BattuneShared", dependencies: ["BattuneDomain"], path: "shared/XPCProtocol"),
        .target(name: "BattuneSystem", dependencies: ["BattuneDomain", "BattuneShared"], path: "app/Battune/Services"),
        .target(name: "BattuneHardware", dependencies: ["BattuneDomain", "BattuneShared", "BattuneSystem"], path: "helper/BattuneHelper", exclude: ["main.swift"], sources: ["Security", "Hardware", "XPC"]),
        .executableTarget(name: "BattuneHelper", dependencies: ["BattuneHardware"], path: "helper/BattuneHelper", exclude: ["Security", "Hardware", "XPC"], sources: ["main.swift"]),
        .executableTarget(name: "Battune", dependencies: ["BattuneDomain", "BattuneSystem", "BattuneShared"], path: "app/Battune", exclude: ["Models", "Persistence", "Statistics", "Scheduling", "Services"], sources: ["App", "Views"], resources: [.process("Localization")]),
        .executableTarget(name: "BattuneTests", dependencies: ["BattuneDomain", "BattuneSystem", "BattuneHardware", "BattuneShared", "CBattuneCore"], path: "tests/BattuneTests")
    ]
)
