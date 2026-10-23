// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LangCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LangCore", targets: ["LangCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
    ],
    targets: [
        // MeCab 0.996 (BSD), vendored; see Licenses/.
        .target(
            name: "CMeCab",
            path: "Sources/CMeCab",
            publicHeadersPath: "include",
            // -w: this is unmodified 2008-era upstream code; its warnings are noise. Our own targets keep theirs.
            cxxSettings: [.define("HAVE_CONFIG_H"), .headerSearchPath("."), .unsafeFlags(["-w"])],
            linkerSettings: [.linkedLibrary("iconv")]
        ),
        .target(
            name: "LangCore",
            dependencies: [
                "CMeCab",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            resources: [.copy("Resources/ipadic"), .copy("Resources/dictionaries"), .copy("Resources/Licenses")]
        ),
        .testTarget(name: "LangCoreTests", dependencies: ["LangCore"]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx14
)
