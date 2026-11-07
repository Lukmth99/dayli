// swift-tools-version: 5.9
import PackageDescription

// DayliCore contém apenas regras de negócio puras (Foundation).
// Não depende de SwiftUI, SwiftData, EventKit ou UIKit, para poder ser
// testado rapidamente com `swift test` e reutilizado pelo app e pelos widgets.
let package = Package(
    name: "DayliCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DayliCore", targets: ["DayliCore"])
    ],
    targets: [
        .target(name: "DayliCore"),
        .testTarget(name: "DayliCoreTests", dependencies: ["DayliCore"])
    ]
)
