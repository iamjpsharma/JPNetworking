//
//  CachePolicy.swift
//  JPNetworking
//
//  Cache policy definitions for controlling caching behavior per request.
//  Provides fine-grained control over when to read from and write to cache.
//

import Foundation

/// Cache policy for individual requests
///
/// Defines how caching should behave for specific requests, allowing
/// fine-grained control over cache read/write operations.
///
/// **Usage:**
/// ```swift
/// // Use cache if available, store response in cache
/// let response = await manager.execute(request, as: User.self, cachePolicy: .default)
/// 
/// // Always fetch from network, don't use cache
/// let response = await manager.execute(request, as: User.self, cachePolicy: .networkOnly)
/// 
/// // Use cache only, don't make network request
/// let response = await manager.execute(request, as: User.self, cachePolicy: .cacheOnly)
/// ```
public enum CachePolicy: Sendable, Equatable {
    
    /// Use cache if available, store successful responses
    case `default`
    
    /// Always fetch from network, don't read from cache but store successful responses
    case networkFirst
    
    /// Use cache if available, don't make network request if cached
    case cacheFirst
    
    /// Only use cache, never make network request
    case cacheOnly
    
    /// Only use network, never read from or write to cache
    case networkOnly
    
    /// Use cache if available, always fetch from network and update cache
    case cacheAndNetwork
    
    /// Custom cache policy with explicit read/write behavior
    case custom(shouldReadFromCache: Bool, shouldWriteToCache: Bool)
    
    // MARK: - Computed Properties
    
    /// Whether this policy should read from cache
    public var shouldReadFromCache: Bool {
        switch self {
        case .default, .cacheFirst, .cacheOnly, .cacheAndNetwork:
            return true
        case .networkFirst, .networkOnly:
            return false
        case .custom(let shouldRead, _):
            return shouldRead
        }
    }
    
    /// Whether this policy should write to cache
    public var shouldWriteToCache: Bool {
        switch self {
        case .default, .networkFirst, .cacheAndNetwork:
            return true
        case .cacheFirst, .cacheOnly, .networkOnly:
            return false
        case .custom(_, let shouldWrite):
            return shouldWrite
        }
    }
    
    /// Whether this policy should make network requests
    public var shouldMakeNetworkRequest: Bool {
        switch self {
        case .default, .networkFirst, .networkOnly, .cacheAndNetwork:
            return true
        case .cacheFirst:
            return true // Will make request if cache miss
        case .cacheOnly:
            return false
        case .custom:
            return true // Custom policies assume network requests unless cache-only
        }
    }
    
    /// Whether this policy should make network request even if cache hit
    public var shouldAlwaysMakeNetworkRequest: Bool {
        switch self {
        case .networkFirst, .networkOnly, .cacheAndNetwork:
            return true
        case .default, .cacheFirst, .cacheOnly:
            return false
        case .custom:
            return false
        }
    }
}

// MARK: - Cache Policy Extensions

extension CachePolicy {
    
    /// Cache policy for real-time data that should always be fresh
    public static let realTime = CachePolicy.networkOnly
    
    /// Cache policy for static data that rarely changes
    public static let staticData = CachePolicy.cacheFirst
    
    /// Cache policy for offline-first applications
    public static let offlineFirst = CachePolicy.cacheOnly
    
    /// Cache policy that prioritizes performance over freshness
    public static let performance = CachePolicy.cacheFirst
    
    /// Cache policy that prioritizes freshness over performance
    public static let freshness = CachePolicy.networkFirst
}

// MARK: - Cache Policy Description

extension CachePolicy: CustomStringConvertible {
    public var description: String {
        switch self {
        case .default:
            return "Default (cache-then-network with store)"
        case .networkFirst:
            return "Network First (ignore cache, store response)"
        case .cacheFirst:
            return "Cache First (cache-then-network)"
        case .cacheOnly:
            return "Cache Only (no network requests)"
        case .networkOnly:
            return "Network Only (no caching)"
        case .cacheAndNetwork:
            return "Cache and Network (use cache, always fetch)"
        case .custom(let read, let write):
            return "Custom (read: \(read), write: \(write))"
        }
    }
}

/*
 🗄️ CACHE POLICY ARCHITECTURE EXPLANATION:
 
 1. FLEXIBLE CACHING STRATEGIES:
    - Default: Standard cache-then-network behavior
    - NetworkFirst: Prioritize fresh data, cache for offline use
    - CacheFirst: Prioritize performance, use cache when available
    - CacheOnly: Offline-only mode, never make network requests
    - NetworkOnly: Real-time mode, never use cache
    - CacheAndNetwork: Hybrid approach for critical data
 
 2. FINE-GRAINED CONTROL:
    - Separate read and write cache controls
    - Custom policies for specific use cases
    - Computed properties for easy policy evaluation
    - Predefined policies for common scenarios
 
 3. USE CASE OPTIMIZATION:
    - Real-time data (stock prices, live scores)
    - Static data (user profiles, settings)
    - Offline-first applications
    - Performance vs freshness trade-offs
 
 4. INTEGRATION BENEFITS:
    - Per-request cache policy override
    - Consistent behavior across the framework
    - Easy to understand and debug
    - Extensible for future cache strategies
 */
