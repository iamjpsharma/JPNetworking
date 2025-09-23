// swift-tools-version: 5.7
// SwiftNet - Production-Ready Networking Framework
// Minimum Swift 5.7 for async/await and modern concurrency support

import PackageDescription

let package = Package(
    name: "SwiftNet",
    
    // MARK: - Platform Support
    // Supporting modern iOS/macOS versions for optimal performance and feature set
    platforms: [
        .iOS(.v13),      // iOS 13+ for async/await, Combine, and modern networking APIs
        .macOS(.v10_15), // macOS 10.15+ for Catalyst support and desktop apps
        .tvOS(.v13),     // tvOS support for Apple TV applications
        .watchOS(.v6),   // watchOS support for Apple Watch applications
    ],
    
    // MARK: - Products
    // JPNetworking library - the main networking framework
    products: [
        .library(
            name: "JPNetworking",
            targets: ["JPNetworking"]
        ),
    ],
    
    // MARK: - Dependencies
    // Zero external dependencies for maximum compatibility and minimal footprint
    dependencies: [
        // Pure Swift/Foundation implementation - no external dependencies
    ],
    
    // MARK: - Targets
    targets: [
        // MARK: Main Framework Target
        .target(
            name: "JPNetworking",
            dependencies: [],
            path: "Sources/JPNetworking"
        ),
        
        // MARK: Test Target
        .testTarget(
            name: "JPNetworkingTests",
            dependencies: ["JPNetworking"],
            path: "Tests/JPNetworkingTests"
        ),
    ]
)

/*
 🏗️ PACKAGE ARCHITECTURE DECISIONS:
 
 1. SWIFT VERSION (5.7):
    - Enables async/await for modern networking
    - Supports structured concurrency
    - Compatible with Xcode 14+ and recent iOS versions
    - Balances modern features with broad compatibility
 
 2. PLATFORM STRATEGY:
    - iOS 13+: Minimum for async/await and URLSession improvements
    - macOS 10.15+: Catalyst apps and desktop networking
    - tvOS/watchOS: Complete Apple ecosystem coverage
 
 3. ZERO DEPENDENCIES:
    - Pure Swift/Foundation implementation
    - No version conflicts with host applications
    - Smaller binary size and faster compilation
    - Enhanced security through reduced attack surface
 
 4. TARGET STRUCTURE:
    - Single library target for simplicity
    - Comprehensive test suite for reliability
    - Clear separation between framework and tests
 */
