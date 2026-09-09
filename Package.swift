// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LR-Parsing",
    platforms: [.macOS(.v11), .iOS(.v14)],
    products: [
        .library(name: "LR-Parsing", targets: ["LR-Parsing"]),
        .executable(name: "lr-parse", targets: ["lr-parse"]),
        .executable(name: "lr-conformance", targets: ["lr-conformance"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "2.0.0"),
        .package(url: "https://github.com/hakkabon/Grammar.git", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/hakkabon/Parser.git", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/hakkabon/Lexer.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .target(
            name: "LR-Parsing",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
                .product(name: "Lexer", package: "Lexer"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
                .product(name: "TerminalColors", package: "TerminalColors"),
            ],
            path: "Sources/LR-Parsing"
        ),
        .testTarget(
            name: "LR-ParsingTests",
            dependencies: [
                "LR-Parsing",
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
            ]
        ),
        .executableTarget(
            name: "lr-conformance",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Lexer", package: "Lexer"),
                .product(name: "Parser", package: "Parser"),
                "LR-Parsing",
            ],
            path: "Sources/conformance"
        ),
        // Move executable target to its destination when library confirmed working.
        .executableTarget(
            name: "lr-parse",
            dependencies: [
                "LR-Parsing",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ShellOut", package: "shellout"),
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
            ],
            path: "Sources/parse"
        ),
    ]
)
