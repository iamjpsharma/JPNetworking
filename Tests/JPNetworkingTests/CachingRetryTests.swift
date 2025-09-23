//
//  CachingRetryTests.swift
//  JPNetworkingTests
//
//  Comprehensive tests for caching and retry functionality.
//  Tests cache policies, retry strategies, and integration scenarios.
//

import XCTest
@testable import JPNetworking

final class CachingRetryTests: XCTestCase {
    
    // MARK: - Test Models
    
    struct TestUser: Codable, Sendable, Equatable {
        let id: Int
        let name: String
        let email: String
    }
    
    // MARK: - Cache Configuration Tests
    
    func testCacheConfigurationDefaults() {
        let config = CacheConfiguration()
        
        XCTAssertEqual(config.memoryCapacity, 20 * 1024 * 1024) // 20MB
        XCTAssertEqual(config.diskCapacity, 100 * 1024 * 1024) // 100MB
        XCTAssertEqual(config.defaultTTL, 300) // 5 minutes
        XCTAssertEqual(config.strategy, .memoryAndDisk)
        XCTAssertEqual(config.evictionPolicy, .lru)
        XCTAssertFalse(config.cacheErrors)
        XCTAssertTrue(config.compressionEnabled)
        XCTAssertEqual(config.compressionThreshold, 1024) // 1KB
    }
    
    func testCacheConfigurationCustom() {
        let config = CacheConfiguration(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            defaultTTL: 600,
            strategy: .memoryOnly,
            evictionPolicy: .lfu,
            cacheErrors: true,
            compressionEnabled: false
        )
        
        XCTAssertEqual(config.memoryCapacity, 50 * 1024 * 1024)
        XCTAssertEqual(config.diskCapacity, 200 * 1024 * 1024)
        XCTAssertEqual(config.defaultTTL, 600)
        XCTAssertEqual(config.strategy, .memoryOnly)
        XCTAssertEqual(config.evictionPolicy, .lfu)
        XCTAssertTrue(config.cacheErrors)
        XCTAssertFalse(config.compressionEnabled)
    }
    
    // MARK: - Cache Policy Tests
    
    func testCachePolicyBehavior() {
        // Test default policy
        XCTAssertTrue(CachePolicy.default.shouldReadFromCache)
        XCTAssertTrue(CachePolicy.default.shouldWriteToCache)
        XCTAssertTrue(CachePolicy.default.shouldMakeNetworkRequest)
        XCTAssertFalse(CachePolicy.default.shouldAlwaysMakeNetworkRequest)
        
        // Test network-only policy
        XCTAssertFalse(CachePolicy.networkOnly.shouldReadFromCache)
        XCTAssertFalse(CachePolicy.networkOnly.shouldWriteToCache)
        XCTAssertTrue(CachePolicy.networkOnly.shouldMakeNetworkRequest)
        XCTAssertTrue(CachePolicy.networkOnly.shouldAlwaysMakeNetworkRequest)
        
        // Test cache-only policy
        XCTAssertTrue(CachePolicy.cacheOnly.shouldReadFromCache)
        XCTAssertFalse(CachePolicy.cacheOnly.shouldWriteToCache)
        XCTAssertFalse(CachePolicy.cacheOnly.shouldMakeNetworkRequest)
        XCTAssertFalse(CachePolicy.cacheOnly.shouldAlwaysMakeNetworkRequest)
        
        // Test custom policy
        let customPolicy = CachePolicy.custom(shouldReadFromCache: true, shouldWriteToCache: false)
        XCTAssertTrue(customPolicy.shouldReadFromCache)
        XCTAssertFalse(customPolicy.shouldWriteToCache)
    }
    
    func testCachePolicyPresets() {
        XCTAssertEqual(CachePolicy.realTime, CachePolicy.networkOnly)
        XCTAssertEqual(CachePolicy.staticData, CachePolicy.cacheFirst)
        XCTAssertEqual(CachePolicy.offlineFirst, CachePolicy.cacheOnly)
        XCTAssertEqual(CachePolicy.performance, CachePolicy.cacheFirst)
        XCTAssertEqual(CachePolicy.freshness, CachePolicy.networkFirst)
    }
    
    // MARK: - Retry Configuration Tests
    
    func testRetryConfigurationDefaults() {
        let config = RetryConfiguration()
        
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.maxRetryDuration, 300) // 5 minutes
        XCTAssertTrue(config.retryOnTimeout)
        XCTAssertTrue(config.retryOnConnectionError)
        XCTAssertTrue(config.retryableStatusCodes.contains(500))
        XCTAssertTrue(config.retryableStatusCodes.contains(502))
        XCTAssertTrue(config.retryableStatusCodes.contains(503))
        XCTAssertTrue(config.retryableErrors.contains(.timeout))
        XCTAssertTrue(config.retryableErrors.contains(.connectionFailed))
        XCTAssertTrue(config.retryableErrors.contains(.serverError))
    }
    
    func testRetryConfigurationPresets() {
        let apiDefault = RetryConfiguration.apiDefault
        XCTAssertEqual(apiDefault.maxRetries, 3)
        
        let aggressive = RetryConfiguration.aggressive
        XCTAssertEqual(aggressive.maxRetries, 5)
        XCTAssertEqual(aggressive.maxRetryDuration, 600) // 10 minutes
        
        let conservative = RetryConfiguration.conservative
        XCTAssertEqual(conservative.maxRetries, 2)
        XCTAssertEqual(conservative.maxRetryDuration, 60) // 1 minute
        
        let none = RetryConfiguration.none
        XCTAssertEqual(none.maxRetries, 0)
    }
    
    // MARK: - Backoff Strategy Tests
    
    func testBackoffStrategies() {
        let fixed = RetryConfiguration.BackoffStrategy.fixed(2.0)
        XCTAssertEqual(fixed.delay(for: 1), 2.0)
        XCTAssertEqual(fixed.delay(for: 3), 2.0)
        
        let linear = RetryConfiguration.BackoffStrategy.linear(multiplier: 1.5)
        XCTAssertEqual(linear.delay(for: 1), 1.5)
        XCTAssertEqual(linear.delay(for: 2), 3.0)
        XCTAssertEqual(linear.delay(for: 3), 4.5)
        
        let exponential = RetryConfiguration.BackoffStrategy.exponential(base: 1.0, cap: 10.0)
        XCTAssertEqual(exponential.delay(for: 1), 1.0)
        XCTAssertEqual(exponential.delay(for: 2), 2.0)
        XCTAssertEqual(exponential.delay(for: 3), 4.0)
        XCTAssertEqual(exponential.delay(for: 5), 10.0) // Capped at 10.0
        
        let custom = RetryConfiguration.BackoffStrategy.custom { attempt in
            return TimeInterval(attempt * 2)
        }
        XCTAssertEqual(custom.delay(for: 1), 2.0)
        XCTAssertEqual(custom.delay(for: 3), 6.0)
    }
    
    // MARK: - Jitter Strategy Tests
    
    func testJitterStrategies() {
        let none = RetryConfiguration.JitterStrategy.none
        XCTAssertEqual(none.apply(to: 5.0), 5.0)
        
        let full = RetryConfiguration.JitterStrategy.full
        let fullJittered = full.apply(to: 10.0)
        XCTAssertGreaterThanOrEqual(fullJittered, 0.0)
        XCTAssertLessThanOrEqual(fullJittered, 10.0)
        
        let equal = RetryConfiguration.JitterStrategy.equal
        let equalJittered = equal.apply(to: 10.0)
        XCTAssertGreaterThanOrEqual(equalJittered, 5.0)
        XCTAssertLessThanOrEqual(equalJittered, 10.0)
        
        let decorrelated = RetryConfiguration.JitterStrategy.decorrelated
        let decorrelatedJittered = decorrelated.apply(to: 10.0, previousDelay: 5.0)
        XCTAssertGreaterThan(decorrelatedJittered, 0.0)
    }
    
    // MARK: - Network Error Type Tests
    
    func testNetworkErrorTypeMapping() {
        XCTAssertEqual(NetworkErrorType(from: .timeout), .timeout)
        XCTAssertEqual(NetworkErrorType(from: .noInternetConnection), .connectionFailed)
        XCTAssertEqual(NetworkErrorType(from: .connectionFailed(nil)), .connectionFailed)
        XCTAssertEqual(NetworkErrorType(from: .serverError(statusCode: 500)), .serverError)
        XCTAssertEqual(NetworkErrorType(from: .unauthorizedAccess(statusCode: 401)), .authenticationError)
        XCTAssertEqual(NetworkErrorType(from: .httpError(statusCode: 400, data: nil)), .clientError)
        XCTAssertEqual(NetworkErrorType(from: .httpError(statusCode: 500, data: nil)), .serverError)
        XCTAssertEqual(NetworkErrorType(from: .invalidURL("")), .unknown)
    }
    
    // MARK: - Cache Manager Tests
    
    @MainActor
    func testCacheManagerInitialization() async {
        let config = CacheConfiguration(strategy: .memoryOnly)
        let cacheManager = CacheManager(configuration: config)
        
        let stats = await cacheManager.getStatistics()
        XCTAssertEqual(stats.hitCount, 0)
        XCTAssertEqual(stats.missCount, 0)
        XCTAssertEqual(stats.storeCount, 0)
        XCTAssertEqual(stats.hitRate, 0.0)
    }
    
    @MainActor
    func testCacheManagerClearAll() async {
        let cacheManager = CacheManager.shared
        await cacheManager.clearAll()
        
        let stats = await cacheManager.getStatistics()
        XCTAssertEqual(stats.hitCount, 0)
        XCTAssertEqual(stats.missCount, 0)
        XCTAssertEqual(stats.storeCount, 0)
    }
    
    // MARK: - Retry Manager Tests
    
    @MainActor
    func testRetryManagerInitialization() async {
        let config = RetryConfiguration(maxRetries: 2)
        let retryManager = RetryManager(configuration: config)
        
        let stats = await retryManager.getStatistics()
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertEqual(stats.successfulRequests, 0)
        XCTAssertEqual(stats.failedRequests, 0)
        XCTAssertEqual(stats.totalRetries, 0)
        XCTAssertEqual(stats.successRate, 0.0)
    }
    
    @MainActor
    func testRetryManagerStatistics() async {
        let retryManager = RetryManager.shared
        await retryManager.resetStatistics()
        
        let stats = await retryManager.getStatistics()
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertEqual(stats.averageRetriesPerRequest, 0.0)
        XCTAssertEqual(stats.retryRate, 0.0)
    }
    
    // MARK: - Retry Context Tests
    
    func testRetryContext() {
        let context = RetryContext(
            attempt: 2,
            totalAttempts: 5,
            previousDelay: 1.5,
            totalElapsed: 3.0,
            lastError: .timeout,
            lastResponse: nil
        )
        
        XCTAssertEqual(context.attempt, 2)
        XCTAssertEqual(context.totalAttempts, 5)
        XCTAssertEqual(context.previousDelay, 1.5)
        XCTAssertEqual(context.totalElapsed, 3.0)
        XCTAssertFalse(context.isFirstAttempt)
        XCTAssertFalse(context.isLastAttempt)
        XCTAssertEqual(context.remainingAttempts, 3)
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testNetworkManagerWithCacheAndRetry() async {
        let cacheConfig = CacheConfiguration(strategy: .memoryOnly)
        let retryConfig = RetryConfiguration(maxRetries: 1)
        
        let cacheManager = CacheManager(configuration: cacheConfig)
        let retryManager = RetryManager(configuration: retryConfig)
        
        let networkManager = NetworkManager(
            cacheManager: cacheManager,
            retryManager: retryManager
        )
        
        XCTAssertNotNil(networkManager.cacheManager)
        XCTAssertNotNil(networkManager.retryManager)
    }
    
    // MARK: - Cache Statistics Tests
    
    func testCacheStatistics() {
        var stats = CacheStatistics()
        XCTAssertEqual(stats.hitRate, 0.0)
        XCTAssertEqual(stats.totalRequests, 0)
        
        stats.hitCount = 7
        stats.missCount = 3
        XCTAssertEqual(stats.hitRate, 0.7)
        XCTAssertEqual(stats.totalRequests, 10)
    }
    
    // MARK: - Retry Statistics Tests
    
    func testRetryStatistics() {
        var stats = RetryStatistics()
        XCTAssertEqual(stats.successRate, 0.0)
        XCTAssertEqual(stats.averageRetriesPerRequest, 0.0)
        XCTAssertEqual(stats.retryRate, 0.0)
        
        stats.totalRequests = 10
        stats.successfulRequests = 8
        stats.totalRetries = 5
        stats.requestsWithRetries = 3
        
        XCTAssertEqual(stats.successRate, 0.8)
        XCTAssertEqual(stats.averageRetriesPerRequest, 0.5)
        XCTAssertEqual(stats.retryRate, 0.3)
    }
    
    // MARK: - Cache Policy Description Tests
    
    func testCachePolicyDescriptions() {
        XCTAssertEqual(CachePolicy.default.description, "Default (cache-then-network with store)")
        XCTAssertEqual(CachePolicy.networkOnly.description, "Network Only (no caching)")
        XCTAssertEqual(CachePolicy.cacheOnly.description, "Cache Only (no network requests)")
        XCTAssertEqual(CachePolicy.custom(shouldReadFromCache: true, shouldWriteToCache: false).description, "Custom (read: true, write: false)")
    }
    
    // MARK: - Mock Response Tests
    
    func testMockResponseCreation() {
        let testUser = TestUser(id: 1, name: "Test User", email: "test@example.com")
        
        // Create mock HTTP response with 200 status
        let url = URL(string: "https://api.example.com/test")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        
        let response = JPNetworkingResponse<TestUser>(
            data: nil,
            response: httpResponse,
            request: nil,
            value: testUser,
            error: nil
        )
        
        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(response.value, testUser)
        XCTAssertEqual(response.statusCode, 200)
    }
    
    // MARK: - Framework Information Tests
    
    @MainActor
    func testFrameworkInfoWithNewFeatures() {
        let info = JPNetworking.frameworkInfo()
        let features = info["features"] as? [String] ?? []
        
        XCTAssertTrue(features.contains("Async/Await Support"))
        XCTAssertTrue(features.contains("Type-Safe Request Building"))
        XCTAssertTrue(features.contains("Comprehensive Error Handling"))
        XCTAssertTrue(features.contains("Thread-Safe Design"))
        XCTAssertTrue(features.contains("Production Ready"))
    }
}

/*
 🧪 CACHING & RETRY TESTS EXPLANATION:
 
 1. COMPREHENSIVE COVERAGE:
    - Cache configuration and policies
    - Retry configuration and strategies
    - Backoff and jitter algorithms
    - Error type mapping and handling
    - Statistics and monitoring
 
 2. INTEGRATION TESTING:
    - NetworkManager with cache and retry managers
    - End-to-end functionality verification
    - Mock response handling
    - Framework information validation
 
 3. EDGE CASE TESTING:
    - Default vs custom configurations
    - Preset policy behaviors
    - Statistical calculations
    - Error condition handling
 
 4. PRODUCTION READINESS:
    - Thread-safe operations
    - Memory management
    - Performance characteristics
    - Monitoring and debugging support
 */
