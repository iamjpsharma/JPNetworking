//
//  JPNetworking.swift
//  JPNetworking
//
//  Main API facade for JPNetworking framework.
//  Provides convenient static methods and global configuration.
//

import Foundation

/// JPNetworking - Advanced Swift Networking Framework
///
/// A modern, production-ready networking framework that rivals AFNetworking and Alamofire.
/// Built with modern Swift concurrency, type safety, and developer experience in mind.
///
/// **Key Features:**
/// - Modern async/await APIs with Swift concurrency
/// - Type-safe request building with fluent API
/// - Comprehensive error handling and recovery
/// - Advanced caching with intelligent eviction
/// - Intelligent retry logic with exponential backoff
/// - Built-in authentication support
/// - Request/response interceptors
/// - Advanced logging and monitoring
///
/// **Basic Usage:**
/// ```swift
/// // Simple GET request
/// let users = await JPNetworking.get("https://api.example.com/users", as: [User].self)
/// 
/// // POST with JSON body
/// let response = await JPNetworking.post("https://api.example.com/users", body: .json(newUser))
/// 
/// // Configure global settings
/// JPNetworking.configure(
///     baseURL: "https://api.myapp.com",
///     defaultHeaders: ["Authorization": "Bearer \(token)"]
/// )
/// ```
///
/// For more advanced usage, create custom `NetworkManager` instances with specific configurations.
@MainActor
public final class JPNetworking {
    
    // MARK: - Version Information
    
    /// JPNetworking framework version
    public static let version = "1.0.0"
    
    /// JPNetworking framework name
    public static let name = "JPNetworking"
    
    /// Framework build information
    public static let buildInfo = "Production build - \(Date())"
    
    // MARK: - Global Configuration
    
    /// Global NetworkManager instance
    private static var globalManager = NetworkManager.shared
    
    /// Thread-safe access queue for global manager
    private static let configurationQueue = DispatchQueue(label: "JPNetworking.configuration", attributes: .concurrent)
    
    /// Access to the global NetworkManager instance
    public static var manager: NetworkManager {
        return configurationQueue.sync { globalManager }
    }
    
    /// Configure global JPNetworking instance
    /// - Parameters:
    ///   - baseURL: Base URL for all relative requests
    ///   - defaultHeaders: Default headers for all requests
    ///   - timeout: Default timeout for requests
    ///   - allowsCellularAccess: Whether to allow cellular access
    ///   - session: Custom URLSession (optional)
    public static func configure(
        baseURL: String,
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30.0,
        allowsCellularAccess: Bool = true,
        session: URLSession = .shared
    ) {
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            timeout: timeout,
            allowsCellularAccess: allowsCellularAccess
        )
        
        configurationQueue.async(flags: .barrier) {
            globalManager = NetworkManager(configuration: configuration, session: session)
        }
    }
    
    /// Reset global configuration to defaults
    public static func resetConfiguration() {
        configurationQueue.async(flags: .barrier) {
            globalManager = NetworkManager.shared
        }
    }
    
    // MARK: - Convenience Static API - Async/Await
    
    /// Execute custom JPNetworkingRequest with caching and retry support
    /// - Parameters:
    ///   - request: Custom request to execute
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - cachePolicy: Cache policy for this request
    ///   - retryConfiguration: Retry configuration for this request
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func execute<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        cachePolicy: CachePolicy = .default,
        retryConfiguration: RetryConfiguration? = nil
    ) async -> JPNetworkingResponse<T> {
        return await manager.execute(
            request,
            as: type,
            decoder: decoder,
            cachePolicy: cachePolicy,
            retryConfiguration: retryConfiguration
        )
    }
    
    /// GET request with automatic JSON decoding and caching support
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - cachePolicy: Cache policy for this request
    ///   - retryConfiguration: Retry configuration for this request
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func get<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        cachePolicy: CachePolicy = .default,
        retryConfiguration: RetryConfiguration? = nil
    ) async -> JPNetworkingResponse<T> {
        let request = JPNetworkingRequest.get(url)
        return await execute(
            request,
            as: type,
            decoder: decoder,
            cachePolicy: cachePolicy,
            retryConfiguration: retryConfiguration
        )
    }
    
    /// POST request with JSON body
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func post<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.post(url, body: body, as: type, encoder: encoder, decoder: decoder)
    }
    
    /// PUT request with JSON body
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func put<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.put(url, body: body, as: type, encoder: encoder, decoder: decoder)
    }
    
    /// DELETE request
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func delete<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.delete(url, as: type, decoder: decoder)
    }
    
    /// PATCH request with JSON body
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Encodable body object
    ///   - type: Target Decodable type
    ///   - encoder: JSON encoder (optional)
    ///   - decoder: JSON decoder (optional)
    /// - Returns: JPNetworkingResponse with decoded value
    @MainActor
    public static func patch<T: Decodable & Sendable, U: Encodable & Sendable>(
        _ url: String,
        body: U,
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.patch(url, body: body, as: type, encoder: encoder, decoder: decoder)
    }
    
    // MARK: - Raw Data Methods
    
    /// GET request returning raw data
    /// - Parameter url: Request URL (relative or absolute)
    /// - Returns: JPNetworkingResponse with Data
    @MainActor
    public static func getData(_ url: String) async -> JPNetworkingResponse<Data> {
        return await manager.getData(url)
    }
    
    /// POST request with body returning raw data
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - body: Request body
    /// - Returns: JPNetworkingResponse with Data
    @MainActor
    public static func postData(_ url: String, body: RequestBody = .none) async -> JPNetworkingResponse<Data> {
        return await manager.postData(url, body: body)
    }
    
    // MARK: - Batch Operations
    
    /// Execute multiple requests concurrently
    /// - Parameter requests: Array of requests to execute
    /// - Returns: Array of responses in same order
    @MainActor
    public static func executeAll(_ requests: [JPNetworkingRequest]) async -> [JPNetworkingResponse<Data>] {
        return await manager.executeAll(requests)
    }
    
    // MARK: - Convenience Static API - Completion Handlers
    
    /// Execute custom request with completion handler
    /// - Parameters:
    ///   - request: Custom request to execute
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - completion: Completion handler
    /// - Returns: URLSessionDataTask for cancellation
    @MainActor
    @discardableResult
    public static func execute<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        completion: @escaping @Sendable (JPNetworkingResponse<T>) -> Void
    ) -> URLSessionDataTask? {
        return manager.execute(request, as: type, decoder: decoder, completion: completion)
    }
    
    /// GET request with completion handler
    /// - Parameters:
    ///   - url: Request URL (relative or absolute)
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder (optional)
    ///   - completion: Completion handler
    /// - Returns: URLSessionDataTask for cancellation
    @MainActor
    @discardableResult
    public static func get<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        completion: @escaping @Sendable (JPNetworkingResponse<T>) -> Void
    ) -> URLSessionDataTask? {
        let request = JPNetworkingRequest.get(url)
        return execute(request, as: type, decoder: decoder, completion: completion)
    }
}

// MARK: - Framework Information
extension JPNetworking {
    
    /// Get comprehensive framework information
    /// - Returns: Dictionary with framework details
    public static func frameworkInfo() -> [String: Any] {
        return [
            "name": name,
            "version": version,
            "buildInfo": buildInfo,
            "swiftVersion": "5.7+",
            "platforms": ["iOS 13.0+", "macOS 10.15+", "tvOS 13.0+", "watchOS 6.0+"],
            "features": [
                "Async/Await Support",
                "Type-Safe Request Building",
                "Comprehensive Error Handling",
                "Automatic JSON Encoding/Decoding",
                "Thread-Safe Design",
                "Zero Dependencies",
                "Production Ready"
            ]
        ]
    }
    
    /// Print framework information to console
    public static func printFrameworkInfo() {
        let info = frameworkInfo()
        print("🚀 \(info["name"] ?? "JPNetworking") v\(info["version"] ?? "1.0.0")")
        print("📱 Platforms: \((info["platforms"] as? [String])?.joined(separator: ", ") ?? "iOS, macOS, tvOS, watchOS")")
        print("⚡ Features:")
        if let features = info["features"] as? [String] {
            for feature in features {
                print("   • \(feature)")
            }
        }
    }
}
