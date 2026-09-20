// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gootd",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Gootd",
            path: "Sources/Gootd",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Carbon")]
        )
    ]
)
