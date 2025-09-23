//
//  RetryManager.swift
//  JPNetworking
//
//  Advanced retry mechanisms with exponential backoff, jitter, and intelligent retry policies.
//  Provides automatic retry for failed requests with configurable strategies.
//

import Foundation

// MARK: - Retry Configuration

/// Configuration for retry behavior and policies
///
/// Defines retry strategies, backoff algorithms, and conditions for when to retry.
/// Supports exponential backoff, linear backoff, and custom retry policies.
///
/// **Usage:**
/// ```swift
/// let retryConfig = RetryConfiguration(
///     maxRetries: 3,
///     backoffStrategy: .exponential(base: 2.0, cap: 60.0),
///     retryableErrors: [.timeout, .connectionFailed, .serverError]
/// )
/// ```
public struct RetryConfiguration: Sendable {
    
    /// Backoff strategies for retry delays
    public enum BackoffStrategy: Sendable {
        /// Fixed delay between retries
        case fixed(TimeInterval)
        /// Linear increase: delay = attempt * multiplier
        case linear(multiplier: TimeInterval)
        /// Exponential backoff: delay = base^attempt (with optional cap)
        case exponential(base: TimeInterval, cap: TimeInterval?)
        /// Custom backoff function
        case custom(@Sendable (Int) -> TimeInterval)
        
        func delay(for attempt: Int) -> TimeInterval {
            switch self {
            case .fixed(let interval):
                return interval
            case .linear(let multiplier):
                return TimeInterval(attempt) * multiplier
            case .exponential(let base, let cap):
                let delay = base * pow(2.0, TimeInterval(attempt - 1))
                return cap.map { min(delay, $0) } ?? delay
            case .custom(let calculator):
                return calculator(attempt)
            }
        }
    }
    
    /// Jitter strategies to avoid thundering herd
    public enum JitterStrategy: Sendable {
        /// No jitter
        case none
        /// Full jitter: random(0, delay)
        case full
        /// Equal jitter: delay/2 + random(0, delay/2)
        case equal
        /// Decorrelated jitter: random(base, previous_delay * 3)
        case decorrelated
        
        func apply(to delay: TimeInterval, previousDelay: TimeInterval = 0) -> TimeInterval {
            switch self {
            case .none:
                return delay
            case .full:
                return TimeInterval.random(in: 0...delay)
            case .equal:
                let half = delay / 2
                return half + TimeInterval.random(in: 0...half)
            case .decorrelated:
                let min = max(1.0, delay / 3)
                let max = previousDelay * 3
                return TimeInterval.random(in: min...max)
            }
        }
    }
    
    // MARK: - Properties
    
    /// Maximum number of retry attempts
    public let maxRetries: Int
    
    /// Backoff strategy for calculating delays
    public let backoffStrategy: BackoffStrategy
    
    /// Jitter strategy to avoid thundering herd
    public let jitterStrategy: JitterStrategy
    
    /// Maximum total time to spend on retries
    public let maxRetryDuration: TimeInterval
    
    /// HTTP status codes that should trigger retries
    public let retryableStatusCodes: Set<Int>
    
    /// Network errors that should trigger retries
    public let retryableErrors: Set<NetworkErrorType>
    
    /// Whether to retry on timeout errors
    public let retryOnTimeout: Bool
    
    /// Whether to retry on connection errors
    public let retryOnConnectionError: Bool
    
    /// Custom retry condition
    public let customRetryCondition: (@Sendable (JPNetworkingResponse<Data>) -> Bool)?
    
    // MARK: - Initializer
    
    public init(
        maxRetries: Int = 3,
        backoffStrategy: BackoffStrategy = .exponential(base: 1.0, cap: 60.0),
        jitterStrategy: JitterStrategy = .equal,
        maxRetryDuration: TimeInterval = 300, // 5 minutes
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableErrors: Set<NetworkErrorType> = [.timeout, .connectionFailed, .serverError],
        retryOnTimeout: Bool = true,
        retryOnConnectionError: Bool = true,
        customRetryCondition: (@Sendable (JPNetworkingResponse<Data>) -> Bool)? = nil
    ) {
        self.maxRetries = maxRetries
        self.backoffStrategy = backoffStrategy
        self.jitterStrategy = jitterStrategy
        self.maxRetryDuration = maxRetryDuration
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableErrors = retryableErrors
        self.retryOnTimeout = retryOnTimeout
        self.retryOnConnectionError = retryOnConnectionError
        self.customRetryCondition = customRetryCondition
    }
}

// MARK: - Network Error Type

/// Simplified network error types for retry logic
public enum NetworkErrorType: Sendable, Hashable {
    case timeout
    case connectionFailed
    case serverError
    case clientError
    case authenticationError
    case unknown
    
    init(from networkError: NetworkError) {
        switch networkError {
        case .timeout:
            self = .timeout
        case .connectionFailed, .noInternetConnection:
            self = .connectionFailed
        case .serverError:
            self = .serverError
        case .unauthorizedAccess, .forbidden, .authenticationRequired, .invalidCredentials, .tokenExpired, .authenticationFailed:
            self = .authenticationError
        case .httpError(let statusCode, _):
            if (400...499).contains(statusCode) {
                self = .clientError
            } else if (500...599).contains(statusCode) {
                self = .serverError
            } else {
                self = .unknown
            }
        default:
            self = .unknown
        }
    }
}

// MARK: - Retry Context

/// Context information for retry attempts
public struct RetryContext: Sendable {
    public let attempt: Int
    public let totalAttempts: Int
    public let previousDelay: TimeInterval
    public let totalElapsed: TimeInterval
    public let lastError: NetworkError?
    public let lastResponse: JPNetworkingResponse<Data>?
    
    public var isFirstAttempt: Bool { attempt == 1 }
    public var isLastAttempt: Bool { attempt == totalAttempts }
    public var remainingAttempts: Int { totalAttempts - attempt }
}

// MARK: - Retry Manager

/// Advanced retry manager with intelligent backoff and jitter
///
/// Provides automatic retry functionality with configurable strategies,
/// exponential backoff, jitter, and comprehensive retry policies.
///
/// **Features:**
/// - Multiple backoff strategies (fixed, linear, exponential, custom)
/// - Jitter strategies to prevent thundering herd problems
/// - Configurable retry conditions based on errors and status codes
/// - Maximum retry duration limits
/// - Comprehensive retry statistics and monitoring
/// - Thread-safe operations with Swift actors
///
/// **Usage:**
/// ```swift
/// let retryManager = RetryManager(configuration: retryConfig)
/// 
/// let response = await retryManager.executeWithRetry(request) { request in
///     return await networkManager.execute(request)
/// }
/// ```
@globalActor
public actor RetryManager {
    
    public static let shared = RetryManager()
    
    // MARK: - Properties
    
    private let configuration: RetryConfiguration
    private var stats = RetryStatistics()
    
    // MARK: - Initialization
    
    public init(configuration: RetryConfiguration = RetryConfiguration()) {
        self.configuration = configuration
    }
    
    // MARK: - Public API
    
    /// Execute request with retry logic
    /// - Parameters:
    ///   - request: JPNetworking request to execute
    ///   - executor: Async function that executes the request
    /// - Returns: Final response after all retry attempts
    public func executeWithRetry<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        executor: @Sendable (JPNetworkingRequest) async -> JPNetworkingResponse<T>
    ) async -> JPNetworkingResponse<T> {
        
        let startTime = Date()
        var previousDelay: TimeInterval = 0
        var lastResponse: JPNetworkingResponse<Data>?
        
        for attempt in 1...(configuration.maxRetries + 1) {
            let context = RetryContext(
                attempt: attempt,
                totalAttempts: configuration.maxRetries + 1,
                previousDelay: previousDelay,
                totalElapsed: Date().timeIntervalSince(startTime),
                lastError: lastResponse?.error,
                lastResponse: lastResponse
            )
            
            // Execute the request
            let response = await executor(request)
            
            // Check if we should stop retrying
            if shouldStopRetrying(response: response, context: context) {
                updateStatistics(finalAttempt: attempt, success: response.isSuccess)
                return response
            }
            
            // Don't delay after the last attempt
            if attempt <= configuration.maxRetries {
                let delay = calculateDelay(for: attempt, previousDelay: previousDelay)
                previousDelay = delay
                
                // Check if we've exceeded maximum retry duration
                let totalElapsed = Date().timeIntervalSince(startTime)
                if totalElapsed + delay > configuration.maxRetryDuration {
                    updateStatistics(finalAttempt: attempt, success: false)
                    return response
                }
                
                // Wait before next attempt
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            // Convert response to Data response for retry logic
            if let dataResponse = convertToDataResponse(response) {
                lastResponse = dataResponse
            }
        }
        
        // This should never be reached, but return the last response as fallback
        updateStatistics(finalAttempt: configuration.maxRetries + 1, success: false)
        return await executor(request)
    }
    
    /// Execute request with retry logic (Data response)
    /// - Parameters:
    ///   - request: JPNetworking request to execute
    ///   - executor: Async function that executes the request
    /// - Returns: Final Data response after all retry attempts
    public func executeWithRetry(
        _ request: JPNetworkingRequest,
        executor: @Sendable (JPNetworkingRequest) async -> JPNetworkingResponse<Data>
    ) async -> JPNetworkingResponse<Data> {
        
        return await executeWithRetry(request, as: Data.self) { request in
            return await executor(request)
        }
    }
    
    /// Check if a response should be retried
    /// - Parameters:
    ///   - response: Response to check
    ///   - context: Current retry context
    /// - Returns: True if should retry, false otherwise
    public func shouldRetry<T>(response: JPNetworkingResponse<T>, context: RetryContext) -> Bool {
        // Don't retry if we've reached max attempts
        if context.attempt > configuration.maxRetries {
            return false
        }
        
        // Don't retry if we've exceeded max duration
        if context.totalElapsed >= configuration.maxRetryDuration {
            return false
        }
        
        // Don't retry successful responses
        if response.isSuccess {
            return false
        }
        
        // Check custom retry condition first
        if let customCondition = configuration.customRetryCondition,
           let dataResponse = convertToDataResponse(response) {
            return customCondition(dataResponse)
        }
        
        // Check retryable status codes
        if configuration.retryableStatusCodes.contains(response.statusCode) {
            return true
        }
        
        // Check retryable errors
        if let error = response.error {
            let errorType = NetworkErrorType(from: error)
            
            if configuration.retryableErrors.contains(errorType) {
                return true
            }
            
            // Additional specific checks
            switch error {
            case .timeout:
                return configuration.retryOnTimeout
            case .connectionFailed, .noInternetConnection:
                return configuration.retryOnConnectionError
            default:
                break
            }
        }
        
        return false
    }
    
    /// Get retry statistics
    public func getStatistics() -> RetryStatistics {
        return stats
    }
    
    /// Reset retry statistics
    public func resetStatistics() {
        stats = RetryStatistics()
    }
    
    // MARK: - Private Methods
    
    private func shouldStopRetrying<T>(response: JPNetworkingResponse<T>, context: RetryContext) -> Bool {
        return !shouldRetry(response: response, context: context)
    }
    
    private func calculateDelay(for attempt: Int, previousDelay: TimeInterval) -> TimeInterval {
        let baseDelay = configuration.backoffStrategy.delay(for: attempt)
        return configuration.jitterStrategy.apply(to: baseDelay, previousDelay: previousDelay)
    }
    
    private func convertToDataResponse<T>(_ response: JPNetworkingResponse<T>) -> JPNetworkingResponse<Data>? {
        return JPNetworkingResponse<Data>(
            data: response.data,
            response: response.response,
            request: response.request,
            value: response.data,
            error: response.error
        )
    }
    
    private func updateStatistics(finalAttempt: Int, success: Bool) {
        stats.totalRequests += 1
        stats.totalRetries += max(0, finalAttempt - 1)
        
        if success {
            stats.successfulRequests += 1
        } else {
            stats.failedRequests += 1
        }
        
        if finalAttempt > 1 {
            stats.requestsWithRetries += 1
        }
    }
}

// MARK: - Retry Statistics

/// Retry performance statistics
public struct RetryStatistics: Sendable {
    public var totalRequests: Int = 0
    public var successfulRequests: Int = 0
    public var failedRequests: Int = 0
    public var totalRetries: Int = 0
    public var requestsWithRetries: Int = 0
    
    public var successRate: Double {
        return totalRequests > 0 ? Double(successfulRequests) / Double(totalRequests) : 0.0
    }
    
    public var averageRetriesPerRequest: Double {
        return totalRequests > 0 ? Double(totalRetries) / Double(totalRequests) : 0.0
    }
    
    public var retryRate: Double {
        return totalRequests > 0 ? Double(requestsWithRetries) / Double(totalRequests) : 0.0
    }
}

// MARK: - Convenience Extensions

extension RetryConfiguration {
    
    /// Default configuration for API calls
    public static let apiDefault = RetryConfiguration(
        maxRetries: 3,
        backoffStrategy: .exponential(base: 1.0, cap: 30.0),
        jitterStrategy: .equal,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504]
    )
    
    /// Aggressive retry configuration for critical requests
    public static let aggressive = RetryConfiguration(
        maxRetries: 5,
        backoffStrategy: .exponential(base: 0.5, cap: 60.0),
        jitterStrategy: .full,
        maxRetryDuration: 600, // 10 minutes
        retryableStatusCodes: [408, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524]
    )
    
    /// Conservative retry configuration for non-critical requests
    public static let conservative = RetryConfiguration(
        maxRetries: 2,
        backoffStrategy: .linear(multiplier: 2.0),
        jitterStrategy: .equal,
        maxRetryDuration: 60, // 1 minute
        retryableStatusCodes: [500, 502, 503, 504]
    )
    
    /// No retry configuration
    public static let none = RetryConfiguration(
        maxRetries: 0,
        backoffStrategy: .fixed(0),
        jitterStrategy: .none
    )
}

/*
 🔄 RETRY MANAGER ARCHITECTURE EXPLANATION:
 
 1. INTELLIGENT BACKOFF STRATEGIES:
    - Fixed: Constant delay between retries
    - Linear: Increasing delay (attempt * multiplier)
    - Exponential: Exponential backoff with optional cap
    - Custom: User-defined backoff function
 
 2. JITTER STRATEGIES:
    - Full: Random delay from 0 to calculated delay
    - Equal: Half fixed + half random delay
    - Decorrelated: Random delay based on previous attempt
    - Prevents thundering herd problems
 
 3. COMPREHENSIVE RETRY CONDITIONS:
    - HTTP status code based (408, 429, 5xx errors)
    - Network error type based (timeout, connection failures)
    - Custom retry conditions for specific use cases
    - Maximum retry duration limits
 
 4. PRODUCTION FEATURES:
    - Detailed retry statistics and monitoring
    - Thread-safe actor-based implementation
    - Configurable retry policies for different scenarios
    - Integration with existing JPNetworking response system
 
 5. PERFORMANCE OPTIMIZATIONS:
    - Async/await for non-blocking retry delays
    - Efficient retry condition evaluation
    - Memory-efficient context tracking
    - Minimal overhead for successful requests
 */
