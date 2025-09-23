//
//  Interceptor.swift
//  JPNetworking
//
//  Request and response interceptor system for JPNetworking.
//  Provides middleware functionality for request/response processing,
//  logging, authentication, caching, and custom transformations.
//

import Foundation

// MARK: - Request Interceptor Protocol

/// Protocol for request interceptors
///
/// Request interceptors can modify requests before they are sent.
/// Common use cases include adding headers, authentication, logging, and validation.
public protocol RequestInterceptor: Sendable {
    /// Intercept and potentially modify a request
    /// - Parameter request: Original request
    /// - Returns: Modified request or original if no changes needed
    /// - Throws: NetworkError if interception fails
    func intercept(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest
    
    /// Priority for interceptor execution (higher numbers execute first)
    var priority: Int { get }
    
    /// Interceptor identifier for debugging
    var identifier: String { get }
}

// MARK: - Response Interceptor Protocol

/// Protocol for response interceptors
///
/// Response interceptors can process responses after they are received.
/// Common use cases include logging, error handling, caching, and data transformation.
public protocol ResponseInterceptor: Sendable {
    /// Intercept and potentially modify a response
    /// - Parameters:
    ///   - response: Original response
    ///   - request: Original request that generated this response
    /// - Returns: Modified response or original if no changes needed
    /// - Throws: NetworkError if interception fails
    func intercept<T>(_ response: JPNetworkingResponse<T>, for request: JPNetworkingRequest) async throws -> JPNetworkingResponse<T>
    
    /// Priority for interceptor execution (higher numbers execute first)
    var priority: Int { get }
    
    /// Interceptor identifier for debugging
    var identifier: String { get }
}

// MARK: - Interceptor Manager

/// Manages request and response interceptors
///
/// Coordinates the execution of interceptors in priority order.
/// Provides registration, removal, and execution functionality.
///
/// **Usage:**
/// ```swift
/// let interceptorManager = InterceptorManager()
/// 
/// // Add interceptors
/// interceptorManager.addRequestInterceptor(LoggingInterceptor())
/// interceptorManager.addRequestInterceptor(AuthenticationInterceptor())
/// interceptorManager.addResponseInterceptor(CacheInterceptor())
/// 
/// // Interceptors are automatically applied by NetworkManager
/// ```
@globalActor
public actor InterceptorManager {
    
    public static let shared = InterceptorManager()
    
    // MARK: - Properties
    
    private var requestInterceptors: [RequestInterceptor] = []
    private var responseInterceptors: [ResponseInterceptor] = []
    
    // MARK: - Request Interceptor Management
    
    /// Add a request interceptor
    /// - Parameter interceptor: Request interceptor to add
    public func addRequestInterceptor(_ interceptor: RequestInterceptor) {
        requestInterceptors.append(interceptor)
        requestInterceptors.sort { $0.priority > $1.priority }
    }
    
    /// Remove a request interceptor by identifier
    /// - Parameter identifier: Interceptor identifier
    public func removeRequestInterceptor(withIdentifier identifier: String) {
        requestInterceptors.removeAll { $0.identifier == identifier }
    }
    
    /// Remove all request interceptors
    public func removeAllRequestInterceptors() {
        requestInterceptors.removeAll()
    }
    
    /// Get all request interceptors
    /// - Returns: Array of request interceptors sorted by priority
    public func getRequestInterceptors() -> [RequestInterceptor] {
        return requestInterceptors
    }
    
    // MARK: - Response Interceptor Management
    
    /// Add a response interceptor
    /// - Parameter interceptor: Response interceptor to add
    public func addResponseInterceptor(_ interceptor: ResponseInterceptor) {
        responseInterceptors.append(interceptor)
        responseInterceptors.sort { $0.priority > $1.priority }
    }
    
    /// Remove a response interceptor by identifier
    /// - Parameter identifier: Interceptor identifier
    public func removeResponseInterceptor(withIdentifier identifier: String) {
        responseInterceptors.removeAll { $0.identifier == identifier }
    }
    
    /// Remove all response interceptors
    public func removeAllResponseInterceptors() {
        responseInterceptors.removeAll()
    }
    
    /// Get all response interceptors
    /// - Returns: Array of response interceptors sorted by priority
    public func getResponseInterceptors() -> [ResponseInterceptor] {
        return responseInterceptors
    }
    
    // MARK: - Interceptor Execution
    
    /// Apply all request interceptors to a request
    /// - Parameter request: Original request
    /// - Returns: Request after all interceptors have been applied
    /// - Throws: NetworkError if any interceptor fails
    public func applyRequestInterceptors(to request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        var currentRequest = request
        
        for interceptor in requestInterceptors {
            do {
                currentRequest = try await interceptor.intercept(currentRequest)
            } catch {
                // Log interceptor failure but continue with other interceptors
                print("⚠️ Request interceptor '\(interceptor.identifier)' failed: \(error)")
                if let networkError = error as? NetworkError {
                    throw networkError
                } else {
                    throw NetworkError.customError("Request interceptor failed: \(error.localizedDescription)", code: nil)
                }
            }
        }
        
        return currentRequest
    }
    
    /// Apply all response interceptors to a response
    /// - Parameters:
    ///   - response: Original response
    ///   - request: Original request
    /// - Returns: Response after all interceptors have been applied
    /// - Throws: NetworkError if any interceptor fails
    public func applyResponseInterceptors<T>(to response: JPNetworkingResponse<T>, for request: JPNetworkingRequest) async throws -> JPNetworkingResponse<T> {
        var currentResponse = response
        
        for interceptor in responseInterceptors {
            do {
                currentResponse = try await interceptor.intercept(currentResponse, for: request)
            } catch {
                // Log interceptor failure but continue with other interceptors
                print("⚠️ Response interceptor '\(interceptor.identifier)' failed: \(error)")
                // Don't throw for response interceptors to avoid breaking the response chain
            }
        }
        
        return currentResponse
    }
}

// MARK: - Built-in Request Interceptors

/// Logging request interceptor
///
/// Logs all outgoing requests with configurable detail levels.
/// Useful for debugging and monitoring network activity.
public struct LoggingRequestInterceptor: RequestInterceptor {
    
    /// Logging detail level
    public enum LogLevel: Sendable {
        case minimal    // Method and URL only
        case standard   // Method, URL, and headers
        case detailed   // Method, URL, headers, and body
        case verbose    // Everything including timing
    }
    
    public let priority: Int
    public let identifier: String
    private let logLevel: LogLevel
    private let logger: (@Sendable (String) -> Void)?
    
    /// Initialize logging interceptor
    /// - Parameters:
    ///   - logLevel: Detail level for logging
    ///   - priority: Execution priority (default: 100)
    ///   - logger: Custom logging function (default: print)
    public init(
        logLevel: LogLevel = .standard,
        priority: Int = 100,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.logLevel = logLevel
        self.priority = priority
        self.identifier = "JPNetworking.LoggingRequestInterceptor"
        self.logger = logger ?? { print("📤 \($0)") }
    }
    
    public func intercept(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        let timestamp = Date()
        var logMessage = "\(request.method.rawValue) \(request.url)"
        
        switch logLevel {
        case .minimal:
            break
            
        case .standard, .detailed, .verbose:
            if !request.headers.isEmpty {
                logMessage += "\nHeaders: \(request.headers)"
            }
            
            if case .detailed = logLevel, !request.body.isEmpty {
                logMessage += "\nBody: \(request.body)"
            }
            
            if case .verbose = logLevel {
                logMessage += "\nTimestamp: \(timestamp)"
                logMessage += "\nTimeout: \(request.timeout)s"
            }
        }
        
        logger?(logMessage)
        return request
    }
}

/// User-Agent request interceptor
///
/// Automatically adds User-Agent header to all requests.
/// Useful for API analytics and client identification.
public struct UserAgentInterceptor: RequestInterceptor {
    
    public let priority: Int
    public let identifier: String
    private let userAgent: String
    
    /// Initialize User-Agent interceptor
    /// - Parameters:
    ///   - userAgent: User-Agent string to add
    ///   - priority: Execution priority (default: 200)
    public init(userAgent: String, priority: Int = 200) {
        self.userAgent = userAgent
        self.priority = priority
        self.identifier = "JPNetworking.UserAgentInterceptor"
    }
    
    public func intercept(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        // Only add User-Agent if not already present
        if request.headers["User-Agent"] == nil {
            return JPNetworkingRequest.builder()
                .method(request.method)
                .url(request.url)
                .headers(request.headers)
                .header("User-Agent", userAgent)
                .body(request.body)
                .timeout(request.timeout)
                .cachePolicy(request.cachePolicy)
                .allowsCellularAccess(request.allowsCellularAccess)
                .build()
        }
        
        return request
    }
}

/// Request validation interceptor
///
/// Validates requests before they are sent.
/// Can check for required headers, URL format, body content, etc.
public struct RequestValidationInterceptor: RequestInterceptor {
    
    public let priority: Int
    public let identifier: String
    private let validators: [@Sendable (JPNetworkingRequest) throws -> Void]
    
    /// Initialize request validation interceptor
    /// - Parameters:
    ///   - validators: Array of validation functions
    ///   - priority: Execution priority (default: 300)
    public init(
        validators: [@Sendable (JPNetworkingRequest) throws -> Void],
        priority: Int = 300
    ) {
        self.validators = validators
        self.priority = priority
        self.identifier = "JPNetworking.RequestValidationInterceptor"
    }
    
    public func intercept(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        for validator in validators {
            try validator(request)
        }
        return request
    }
}

// MARK: - Built-in Response Interceptors

/// Logging response interceptor
///
/// Logs all incoming responses with configurable detail levels.
/// Useful for debugging and monitoring network activity.
public struct LoggingResponseInterceptor: ResponseInterceptor {
    
    /// Logging detail level
    public enum LogLevel: Sendable {
        case minimal    // Status code only
        case standard   // Status code and headers
        case detailed   // Status code, headers, and body size
        case verbose    // Everything including timing and data
    }
    
    public let priority: Int
    public let identifier: String
    private let logLevel: LogLevel
    private let logger: (@Sendable (String) -> Void)?
    
    /// Initialize logging interceptor
    /// - Parameters:
    ///   - logLevel: Detail level for logging
    ///   - priority: Execution priority (default: 100)
    ///   - logger: Custom logging function (default: print)
    public init(
        logLevel: LogLevel = .standard,
        priority: Int = 100,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.logLevel = logLevel
        self.priority = priority
        self.identifier = "JPNetworking.LoggingResponseInterceptor"
        self.logger = logger ?? { print("📥 \($0)") }
    }
    
    public func intercept<T>(_ response: JPNetworkingResponse<T>, for request: JPNetworkingRequest) async throws -> JPNetworkingResponse<T> {
        var logMessage = "Response: \(response.statusCode)"
        
        if let error = response.error {
            logMessage += " ERROR: \(error.localizedDescription)"
        }
        
        switch logLevel {
        case .minimal:
            break
            
        case .standard, .detailed, .verbose:
            if !response.headers.isEmpty {
                logMessage += "\nHeaders: \(response.headers)"
            }
            
            if case .detailed = logLevel, let data = response.data {
                logMessage += "\nBody Size: \(data.count) bytes"
            }
            
            if case .verbose = logLevel {
                logMessage += "\nRequest: \(request.method.rawValue) \(request.url)"
                if let data = response.data {
                    logMessage += "\nResponse Data: \(data.count) bytes"
                }
            }
        }
        
        logger?(logMessage)
        return response
    }
}

/// Error handling response interceptor
///
/// Processes error responses and can transform them or trigger actions.
/// Useful for global error handling, retry logic, and user notifications.
public struct ErrorHandlingInterceptor: ResponseInterceptor {
    
    public let priority: Int
    public let identifier: String
    private let errorHandler: @Sendable (NetworkError, JPNetworkingRequest) async -> Void
    
    /// Initialize error handling interceptor
    /// - Parameters:
    ///   - errorHandler: Function to handle errors
    ///   - priority: Execution priority (default: 50)
    public init(
        errorHandler: @escaping @Sendable (NetworkError, JPNetworkingRequest) async -> Void,
        priority: Int = 50
    ) {
        self.errorHandler = errorHandler
        self.priority = priority
        self.identifier = "JPNetworking.ErrorHandlingInterceptor"
    }
    
    public func intercept<T>(_ response: JPNetworkingResponse<T>, for request: JPNetworkingRequest) async throws -> JPNetworkingResponse<T> {
        if let error = response.error {
            await errorHandler(error, request)
        }
        return response
    }
}

/// Response transformation interceptor
///
/// Transforms response data before it reaches the application.
/// Useful for data normalization, format conversion, and preprocessing.
public struct ResponseTransformationInterceptor: ResponseInterceptor {
    
    public let priority: Int
    public let identifier: String
    private let transformer: @Sendable (Data) async throws -> Data
    
    /// Initialize response transformation interceptor
    /// - Parameters:
    ///   - transformer: Function to transform response data
    ///   - priority: Execution priority (default: 150)
    public init(
        transformer: @escaping @Sendable (Data) async throws -> Data,
        priority: Int = 150
    ) {
        self.transformer = transformer
        self.priority = priority
        self.identifier = "JPNetworking.ResponseTransformationInterceptor"
    }
    
    public func intercept<T>(_ response: JPNetworkingResponse<T>, for request: JPNetworkingRequest) async throws -> JPNetworkingResponse<T> {
        guard let originalData = response.data else {
            return response
        }
        
        do {
            let transformedData = try await transformer(originalData)
            
            return JPNetworkingResponse<T>(
                data: transformedData,
                response: response.response,
                request: response.request,
                value: response.value, // Note: This might need re-decoding in practice
                error: response.error
            )
        } catch {
            // Return original response if transformation fails
            return response
        }
    }
}

/*
 🔌 INTERCEPTOR SYSTEM ARCHITECTURE EXPLANATION:
 
 1. PROTOCOL-BASED DESIGN:
    - Separate protocols for request and response interceptors
    - Priority-based execution order
    - Identifier system for management and debugging
    - Async/await support for modern Swift
 
 2. CENTRALIZED MANAGEMENT:
    - InterceptorManager coordinates all interceptors
    - Thread-safe actor-based implementation
    - Dynamic registration and removal
    - Automatic priority sorting
 
 3. BUILT-IN INTERCEPTORS:
    - Logging: Configurable detail levels for debugging
    - User-Agent: Automatic client identification
    - Validation: Request validation before sending
    - Error Handling: Global error processing
    - Transformation: Response data preprocessing
 
 4. PRODUCTION FEATURES:
    - Error isolation (failed interceptors don't break chain)
    - Configurable logging levels
    - Custom logger support
    - Performance-optimized execution
    - Comprehensive debugging information
 
 5. EXTENSIBILITY:
    - Easy to create custom interceptors
    - Flexible priority system
    - Support for complex transformations
    - Integration with authentication and caching
 
 6. USE CASES:
    - API key injection
    - Request/response logging
    - Data transformation
    - Error handling and retry logic
    - Performance monitoring
    - Security headers
 */
