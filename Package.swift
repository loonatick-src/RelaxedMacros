// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "RelaxedMacro",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(
            name: "RelaxedMacro",
            targets: ["RelaxedMacro"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"602.0.0"),
    ],
    targets: [
        // Macro implementation using SwiftSyntax
        .macro(
            name: "RelaxedMacroImplementation",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // Client library that exposes the macro
        .target(
            name: "RelaxedMacro",
            dependencies: [
                "RelaxedMacroImplementation",
                .product(name: "RealModule", package: "swift-numerics"),
            ]
        ),
        // Example executable
        .executableTarget(
            name: "RelaxedMacroExamples",
            dependencies: ["RelaxedMacro"]
        ),
        .testTarget(
            name: "RelaxedTests",
            dependencies: [
                "RelaxedMacro",
                "RelaxedMacroImplementation",
                .product(name: "RealModule", package: "swift-numerics"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
