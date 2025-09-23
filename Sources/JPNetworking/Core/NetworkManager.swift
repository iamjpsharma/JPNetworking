//
//  NetworkManager.swift
//  JPNetworking
//
//  Production-ready network manager with modern Swift concurrency.
//  Provides both async/await and completion handler APIs for maximum
//  compatibility and developer experience.
//

import Foundation

// MARK: - Network Configuration

/// Configuration object for NetworkManager instances
///
/// Immutable configuration that defines default behavior for all
/// network requests made through a NetworkManager instance.
///
/// **Usage:**
/// ```swift
/// let config = NetworkConfiguration(
///     baseURL: "https://api.myapp.com",
///     defaultHeaders: [
///         "User-Agent": "MyApp/1.0",
///         "Accept": "application/json"
///     ],
///     timeout: 30.0
/// )
/// let manager = NetworkManager(configuration: config)
/// ```
public struct NetworkConfiguration: Sendable {
    
    /// Base URL for all relative requests
    public let baseURL: String
    
    /// Default headers applied to all requests
    public let defaultHeaders: [String: String]
    
    /// Default timeout for all requests
    public let timeout: TimeInterval
    
    /// Whether to allow cellular network access
    public let allowsCellularAccess: Bool
    
    /// Default cache policy for requests
    public let cachePolicy: URLRequest.CachePolicy
    
    /// Initialize network configuration
    /// - Parameters:
    ///   - baseURL: Base URL for relative requests
    ///   - defaultHeaders: Headers applied to all requests
    ///   - timeout: Default request timeout
    ///   - allowsCellularAccess: Cellular access permission
    ///   - cachePolicy: Default caching policy
    public init(
        baseURL: String = "",
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30.0,
        allowsCellularAccess: Bool = true,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.allowsCellularAccess = allowsCellularAccess
        self.cachePolicy = cachePolicy
    }
}

// MARK: - Network Manager

/// Production-ready network manager for HTTP operations
///
/// Core networking engine that provides both modern async/await APIs
/// and traditional completion handler APIs for maximum compatibility.
///
/// **Key Features:**
/// - Modern Swift concurrency with async/await
/// - Backward compatible completion handler APIs
/// - Comprehensive error handling and validation
/// - Configurable defaults and behavior
/// - Thread-safe operation
/// - Automatic JSON encoding/decoding
/// - Request/response logging capabilities
///
/// **Usage Examples:**
/// ```swift
/// // Modern async/await API
/// let users: JPNetworkingResponse<[User]> = await manager.get("/users", as: [User].self)
/// 
/// // Completion handler API
/// manager.get("/users", as: [User].self) { response in
///     // Handle response
/// }
/// 
/// // Custom request
/// let request = JPNetworkingRequest.builder()
///     .method(.POST)
///     .url("/users")
///     .jsonBody(newUser)
///     .build()
/// let response = await manager.execute(request, as: User.self)
/// ```
@MainActor
public final class NetworkManager: Sendable {
    
    // MARK: - Properties
    
    /// Network configuration for this manager
    public let configuration: NetworkConfiguration
    
    /// URLSession instance for network operations
    public let session: URLSession
    
    /// Cache manager for response caching
    public let cacheManager: CacheManager
    
    /// Retry manager for failed request retries
    public let retryManager: RetryManager
    
    // MARK: - Shared Instance
    
    /// Shared NetworkManager instance for convenience
    public static let shared = NetworkManager()
    
    // MARK: - Initializers
    
    /// Initialize NetworkManager with configuration and session
    /// - Parameters:
    ///   - configuration: Network configuration
    ///   - session: URLSession instance
    ///   - cacheManager: Cache manager instance
    ///   - retryManager: Retry manager instance
    public init(
        configuration: NetworkConfiguration = NetworkConfiguration(),
        session: URLSession = .shared,
        cacheManager: CacheManager = CacheManager.shared,
        retryManager: RetryManager = RetryManager.shared
    ) {
        self.configuration = configuration
        self.session = session
        self.cacheManager = cacheManager
        self.retryManager = retryManager
    }
    
    /// Convenience initializer with base URL
    /// - Parameter baseURL: Base URL for all requests
    public convenience init(baseURL: String) {
        let config = NetworkConfiguration(baseURL: baseURL)
        self.init(configuration: config)
    }
    
    // MARK: - Async/Await API
    
    /// Execute JPNetworkingRequest with async/await (internal method)
    /// - Parameter request: Request to execute
    /// - Returns: JPNetworkingResponse with raw Data
    internal func executeInternal(_ request: JPNetworkingRequest) async -> JPNetworkingResponse<Data> {
        do {
            let urlRequest = try buildURLRequest(from: request)
            let (data, response) = try await session.data(for: urlRequest)
            
            return JPNetworkingResponse<Data>.from(
                data: data,
                response: response,
                error: nil,
                request: request
            )
        } catch {
            return JPNetworkingResponse<Data>(
                data: nil,
                response: nil,
                request: request,
                value: nil,
                error: error as? NetworkError ?? .unknown(error)
            )
        }
    }
    
    /// Execute request and decode JSON response with caching and retry support
    /// - Parameters:
    ///   - request: Request to execute
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - cachePolicy: Override cache policy for this request
    ///   - retryConfiguration: Override retry configuration for this request
    /// - Returns: JPNetworkingResponse with decoded value
    public func execute<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        cachePolicy: CachePolicy = .default,
        retryConfiguration: RetryConfiguration? = nil
    ) async -> JPNetworkingResponse<T> {
        
        // Check cache first if enabled
        if cachePolicy.shouldReadFromCache {
            if let cachedResponse = await cacheManager.retrieve(for: request, as: type) {
                return cachedResponse
            }
        }
        
        // Execute with retry logic
        let finalRetryConfig = retryConfiguration ?? RetryConfiguration.apiDefault
        let retryManagerToUse = RetryManager(configuration: finalRetryConfig)
        
        let response = await retryManagerToUse.executeWithRetry(request, as: type) { request in
            let dataResponse = await self.executeInternal(request)
            return dataResponse.decoded(to: type, using: decoder)
        }
        
        // Cache successful responses if enabled
        if cachePolicy.shouldWriteToCache && response.isSuccess {
            await cacheManager.store(response, for: request)
        }
        
        return response
    }
    
    // MARK: - Convenience Async Methods
    
    /// GET request with automatic JSON decoding
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    public func get<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.get(url)
        return await execute(request, as: type, decoder: decoder)
    }
    
    /// POST request with JSON body and automatic decoding
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    public func post<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.post(url, body: .json(body))
        return await execute(request, as: type, decoder: decoder)
    }
    
    /// PUT request with JSON body and automatic decoding
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    public func put<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.put(url, body: .json(body))
        return await execute(request, as: type, decoder: decoder)
    }
    
    /// DELETE request with automatic JSON decoding
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    public func delete<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.delete(url)
        return await execute(request, as: type, decoder: decoder)
    }
    
    /// PATCH request with JSON body and automatic decoding
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    public func patch<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.patch(url, body: .json(body))
        return await execute(request, as: type, decoder: decoder)
    }
    
    // MARK: - Raw Data Methods
    
    /// GET request returning raw data
    /// - Parameter url: Request URL (relative or absolute)
    /// - Returns: JPNetworkingResponse with Data
    public func getData(_ url: String) async -> JPNetworkingResponse<Data> {
        let request = JPNetworkingRequest.get(url)
        return await execute(request, as: Data.self)
    }
    
    /// POST request with body returning raw data
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Request body
    /// - Returns: JPNetworkingResponse with Data
    public func postData(_ url: String, body: RequestBody = .none) async -> JPNetworkingResponse<Data> {
        let request = JPNetworkingRequest.post(url, body: body)
        return await execute(request, as: Data.self)
    }
    
    // MARK: - Completion Handler API
    
    /// Execute request with completion handler
    /// - Parameters:
    ///   - request: Request to execute
    ///   - completion: Completion handler
    /// - Returns: URLSessionDataTask (can be cancelled)
    @discardableResult
    public func execute(
        _ request: JPNetworkingRequest,
        completion: @escaping @Sendable (JPNetworkingResponse<Data>) -> Void
    ) -> URLSessionDataTask? {
        do {
            let urlRequest = try buildURLRequest(from: request)
            
            let task = session.dataTask(with: urlRequest) { data, response, error in
                let dataResponse = JPNetworkingResponse<Data>.from(
                    data: data,
                    response: response,
                    error: error,
                    request: request
                )
                
                Task { @MainActor in
                    completion(dataResponse)
                }
            }
            
            task.resume()
            return task
        } catch {
            let errorResponse = JPNetworkingResponse<Data>(
                data: nil,
                response: nil,
                request: request,
                value: nil,
                error: error as? NetworkError ?? .unknown(error)
            )
            
            Task { @MainActor in
                completion(errorResponse)
            }
            return nil
        }
    }
    
    /// Execute request with JSON decoding and completion handler
    /// - Parameters:
    ///   - request: Request to execute
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - completion: Completion handler
    /// - Returns: URLSessionDataTask (can be cancelled)
    @discardableResult
    public func execute<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        completion: @escaping @Sendable (JPNetworkingResponse<T>) -> Void
    ) -> URLSessionDataTask? {
        return execute(request) { dataResponse in
            let decodedResponse = dataResponse.decoded(to: type, using: decoder)
            completion(decodedResponse)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build URLRequest from JPNetworkingRequest with configuration applied
    /// - Parameter request: JPNetworkingRequest to convert
    /// - Returns: Configured URLRequest
    /// - Throws: NetworkError if building fails
    private func buildURLRequest(from request: JPNetworkingRequest) throws -> URLRequest {
        // Validate request first
        try request.validate()
        
        // Convert to URLRequest with base URL
        var urlRequest = try request.toURLRequest(baseURL: configuration.baseURL)
        
        // Apply configuration defaults (request values take precedence)
        if urlRequest.timeoutInterval == 30.0 { // Default timeout
            urlRequest.timeoutInterval = configuration.timeout
        }
        
        if urlRequest.cachePolicy == .useProtocolCachePolicy { // Default cache policy
            urlRequest.cachePolicy = configuration.cachePolicy
        }
        
        urlRequest.allowsCellularAccess = configuration.allowsCellularAccess
        
        // Add default headers (request headers take precedence)
        for (key, value) in configuration.defaultHeaders {
            if urlRequest.value(forHTTPHeaderField: key) == nil {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        return urlRequest
    }
}

// MARK: - NetworkManager Configuration Updates
extension NetworkManager {
    
    /// Create new NetworkManager with updated base URL
    /// - Parameter baseURL: New base URL
    /// - Returns: New NetworkManager instance
    public func with(baseURL: String) -> NetworkManager {
        let newConfig = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: configuration.defaultHeaders,
            timeout: configuration.timeout,
            allowsCellularAccess: configuration.allowsCellularAccess,
            cachePolicy: configuration.cachePolicy
        )
        return NetworkManager(configuration: newConfig, session: session)
    }
    
    /// Create new NetworkManager with additional headers
    /// - Parameter headers: Headers to add/override
    /// - Returns: New NetworkManager instance
    public func with(headers: [String: String]) -> NetworkManager {
        var newHeaders = configuration.defaultHeaders
        for (key, value) in headers {
            newHeaders[key] = value
        }
        
        let newConfig = NetworkConfiguration(
            baseURL: configuration.baseURL,
            defaultHeaders: newHeaders,
            timeout: configuration.timeout,
            allowsCellularAccess: configuration.allowsCellularAccess,
            cachePolicy: configuration.cachePolicy
        )
        return NetworkManager(configuration: newConfig, session: session)
    }
    
    /// Create new NetworkManager with updated timeout
    /// - Parameter timeout: New timeout value
    /// - Returns: New NetworkManager instance
    public func with(timeout: TimeInterval) -> NetworkManager {
        let newConfig = NetworkConfiguration(
            baseURL: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            timeout: timeout,
            allowsCellularAccess: configuration.allowsCellularAccess,
            cachePolicy: configuration.cachePolicy
        )
        return NetworkManager(configuration: newConfig, session: session)
    }
    
    /// Create new NetworkManager with custom URLSession
    /// - Parameter session: Custom URLSession
    /// - Returns: New NetworkManager instance
    public func with(session: URLSession) -> NetworkManager {
        return NetworkManager(configuration: configuration, session: session)
    }
}

// MARK: - Batch Operations
extension NetworkManager {
    
    /// Execute multiple requests concurrently
    /// - Parameter requests: Array of requests to execute
    /// - Returns: Array of responses in same order as requests
    public func executeAll(_ requests: [JPNetworkingRequest]) async -> [JPNetworkingResponse<Data>] {
        await withTaskGroup(of: (Int, JPNetworkingResponse<Data>).self) { group in
            // Add tasks for each request
            for (index, request) in requests.enumerated() {
                group.addTask {
                    let response = await self.executeInternal(request)
                    return (index, response)
                }
            }
            
            // Collect results and sort by original order
            var results: [(Int, JPNetworkingResponse<Data>)] = []
            for await result in group {
                results.append(result)
            }
            
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }
    
    /// Execute multiple requests with different types concurrently
    /// - Parameter operations: Array of async operations
    /// - Returns: Array of results
    public func executeAll<T>(_ operations: [() async -> T]) async -> [T] {
        await withTaskGroup(of: (Int, T).self) { group in
            for (index, operation) in operations.enumerated() {
                group.addTask {
                    let result = await operation()
                    return (index, result)
                }
            }
            
            var results: [(Int, T)] = []
            for await result in group {
                results.append(result)
            }
            
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }
}

/*
 🌐 NETWORKMANAGER ARCHITECTURE EXPLANATION:
 
 1. MODERN SWIFT CONCURRENCY:
    - @MainActor for thread safety
    - Async/await APIs for modern Swift development
    - Structured concurrency with TaskGroup for batch operations
    - Sendable conformance for safe concurrent access
 
 2. BACKWARD COMPATIBILITY:
    - Completion handler APIs for legacy code
    - URLSessionDataTask return values for cancellation
    - Traditional callback patterns alongside modern async/await
 
 3. COMPREHENSIVE API DESIGN:
    - Generic methods for any Decodable type
    - Convenience methods for common HTTP operations
    - Raw data methods for non-JSON responses
    - Batch operation support for multiple concurrent requests
 
 4. CONFIGURATION MANAGEMENT:
    - Immutable NetworkConfiguration for thread safety
    - Builder pattern for creating configured instances
    - Default value application with request override capability
    - Flexible header and timeout management
 
 5. ERROR HANDLING INTEGRATION:
    - Seamless integration with NetworkError system
    - Proper error propagation through async chains
    - URLError to NetworkError conversion
    - Validation at multiple levels
 
 6. PRODUCTION FEATURES:
    - Thread-safe design throughout
    - Proper resource management
    - Cancellation support via URLSessionDataTask
    - Comprehensive logging and debugging support
    - Memory efficient batch operations
 
 7. PERFORMANCE OPTIMIZATIONS:
    - Concurrent request execution
    - Minimal object allocations
    - Efficient URLRequest building
    - Lazy evaluation where appropriate
 */
