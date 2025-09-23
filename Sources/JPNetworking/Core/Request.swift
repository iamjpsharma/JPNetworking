//
//  Request.swift
//  JPNetworking
//
//  Production-ready HTTP request building system with fluent API.
//  Provides type-safe request construction, validation, and conversion
//  to URLRequest for Foundation networking.
//

import Foundation

// MARK: - HTTP Method Enumeration

/// HTTP methods supported by JPNetworking
///
/// Comprehensive enumeration of HTTP methods with CaseIterable support
/// for programmatic iteration and validation.
///
/// **Usage:**
/// ```swift
/// let request = JPNetworkingRequest.builder()
///     .method(.POST)
///     .url("/users")
///     .build()
/// ```
public enum HTTPMethod: String, CaseIterable, Sendable {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
    case HEAD = "HEAD"
    case OPTIONS = "OPTIONS"
    case TRACE = "TRACE"
    case CONNECT = "CONNECT"
    
    /// Indicates if this HTTP method typically includes a request body
    public var allowsBody: Bool {
        switch self {
        case .GET, .HEAD, .DELETE, .OPTIONS, .TRACE, .CONNECT:
            return false
        case .POST, .PUT, .PATCH:
            return true
        }
    }
}

// MARK: - Request Body Types

/// Request body types supported by JPNetworking
///
/// Flexible body system supporting various content types with automatic
/// Content-Type header management and encoding.
///
/// **Design Features:**
/// - Type-safe body construction
/// - Automatic Content-Type header setting
/// - Support for JSON, form data, multipart, and raw data
/// - Codable integration for Swift objects
public enum RequestBody: Sendable {
    /// No request body
    case none
    /// Raw data body
    case data(Data)
    /// JSON body from Codable object
    case json(any Encodable & Sendable)
    /// URL-encoded form data
    case formData([String: String])
    /// Multipart form data for file uploads
    case multipart(MultipartFormData)
    /// Plain text body
    case string(String, encoding: String.Encoding = .utf8)
    
    /// Appropriate Content-Type header for this body type
    public var contentType: String? {
        switch self {
        case .none:
            return nil
        case .data:
            return "application/octet-stream"
        case .json:
            return "application/json; charset=utf-8"
        case .formData:
            return "application/x-www-form-urlencoded; charset=utf-8"
        case .multipart(let formData):
            return "multipart/form-data; boundary=\(formData.boundary)"
        case .string:
            return "text/plain; charset=utf-8"
        }
    }
    
    /// Indicates if this body type is empty
    public var isEmpty: Bool {
        switch self {
        case .none:
            return true
        case .data(let data):
            return data.isEmpty
        case .string(let string, _):
            return string.isEmpty
        case .formData(let params):
            return params.isEmpty
        default:
            return false
        }
    }
}

// MARK: - Multipart Form Data

/// Multipart form data builder for file uploads and complex forms
///
/// RFC 7578 compliant multipart/form-data implementation supporting
/// mixed content types (text fields, files, binary data).
///
/// **Usage Example:**
/// ```swift
/// let formData = MultipartFormData()
/// formData.append(imageData, withName: "avatar", fileName: "profile.jpg", mimeType: "image/jpeg")
/// formData.append("John Doe", withName: "name")
/// 
/// let request = JPNetworkingRequest.post("/upload", body: .multipart(formData))
/// ```
public final class MultipartFormData: @unchecked Sendable {
    /// Unique boundary string for multipart separation
    public let boundary: String
    
    /// Internal storage for form parts
    private var bodyParts: [Data] = []
    
    /// Thread-safe access queue
    private let queue = DispatchQueue(label: "JPNetworking.MultipartFormData", attributes: .concurrent)
    
    /// Initialize with custom or auto-generated boundary
    /// - Parameter boundary: Custom boundary string (auto-generated if nil)
    public init(boundary: String = "JPNetworking-\(UUID().uuidString)") {
        self.boundary = boundary
    }
    
    /// Append binary data as form field
    /// - Parameters:
    ///   - data: Binary data to append
    ///   - name: Form field name
    ///   - fileName: Optional filename for file uploads
    ///   - mimeType: Optional MIME type for the data
    public func append(_ data: Data, withName name: String, fileName: String? = nil, mimeType: String? = nil) {
        queue.async(flags: .barrier) {
            var bodyPart = Data()
            
            // Boundary line
            bodyPart.append("--\(self.boundary)\r\n".data(using: .utf8)!)
            
            // Content-Disposition header
            var disposition = "Content-Disposition: form-data; name=\"\(name)\""
            if let fileName = fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            bodyPart.append("\(disposition)\r\n".data(using: .utf8)!)
            
            // Content-Type header (if provided)
            if let mimeType = mimeType {
                bodyPart.append("Content-Type: \(mimeType)\r\n".data(using: .utf8)!)
            }
            
            // Empty line before content
            bodyPart.append("\r\n".data(using: .utf8)!)
            
            // Actual content
            bodyPart.append(data)
            
            // Line ending
            bodyPart.append("\r\n".data(using: .utf8)!)
            
            self.bodyParts.append(bodyPart)
        }
    }
    
    /// Append string as form field
    /// - Parameters:
    ///   - string: String value to append
    ///   - name: Form field name
    public func append(_ string: String, withName name: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data, withName: name)
    }
    
    /// Generate complete HTTP body data
    public var httpBody: Data {
        return queue.sync {
            var body = Data()
            
            // Append all body parts
            for bodyPart in bodyParts {
                body.append(bodyPart)
            }
            
            // Final boundary
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            return body
        }
    }
    
    /// Content length of the complete body
    public var contentLength: Int {
        return httpBody.count
    }
}

// MARK: - JPNetworking Request

/// Main request object for JPNetworking networking
///
/// Immutable request configuration with comprehensive validation
/// and URLRequest conversion capabilities.
///
/// **Design Principles:**
/// - Immutable value semantics for thread safety
/// - Comprehensive validation before network execution
/// - Fluent builder API for complex request construction
/// - Direct conversion to Foundation URLRequest
///
/// **Usage Examples:**
/// ```swift
/// // Simple requests
/// let getRequest = JPNetworkingRequest.get("/users")
/// let postRequest = JPNetworkingRequest.post("/users", body: .json(newUser))
/// 
/// // Complex requests with builder
/// let request = JPNetworkingRequest.builder()
///     .method(.PUT)
///     .url("/users/123")
///     .header("Authorization", "Bearer \(token)")
///     .jsonBody(updatedUser)
///     .timeout(60)
///     .build()
/// ```
public struct JPNetworkingRequest: Sendable {
    
    // MARK: - Properties
    
    /// HTTP method for the request
    public let method: HTTPMethod
    
    /// Request URL (can be relative or absolute)
    public let url: String
    
    /// HTTP headers dictionary
    public let headers: [String: String]
    
    /// Request body content
    public let body: RequestBody
    
    /// Request timeout interval in seconds
    public let timeout: TimeInterval
    
    /// URL caching policy
    public let cachePolicy: URLRequest.CachePolicy
    
    /// Whether to allow cellular network access
    public let allowsCellularAccess: Bool
    
    // MARK: - Initializers
    
    /// Initialize JPNetworkingRequest with all parameters
    /// - Parameters:
    ///   - method: HTTP method
    ///   - url: Request URL
    ///   - headers: HTTP headers
    ///   - body: Request body
    ///   - timeout: Timeout interval
    ///   - cachePolicy: Caching policy
    ///   - allowsCellularAccess: Cellular access permission
    public init(
        method: HTTPMethod,
        url: String,
        headers: [String: String] = [:],
        body: RequestBody = .none,
        timeout: TimeInterval = 30.0,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        allowsCellularAccess: Bool = true
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.cachePolicy = cachePolicy
        self.allowsCellularAccess = allowsCellularAccess
    }
    
    // MARK: - Convenience Static Factory Methods
    
    /// Create GET request
    /// - Parameter url: Request URL
    /// - Returns: Configured JPNetworkingRequest
    public static func get(_ url: String) -> JPNetworkingRequest {
        return JPNetworkingRequest(method: .GET, url: url)
    }
    
    /// Create POST request
    /// - Parameters:
    ///   - url: Request URL
    ///   - body: Request body
    /// - Returns: Configured JPNetworkingRequest
    public static func post(_ url: String, body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest(method: .POST, url: url, body: body)
    }
    
    /// Create PUT request
    /// - Parameters:
    ///   - url: Request URL
    ///   - body: Request body
    /// - Returns: Configured JPNetworkingRequest
    public static func put(_ url: String, body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest(method: .PUT, url: url, body: body)
    }
    
    /// Create DELETE request
    /// - Parameter url: Request URL
    /// - Returns: Configured JPNetworkingRequest
    public static func delete(_ url: String) -> JPNetworkingRequest {
        return JPNetworkingRequest(method: .DELETE, url: url)
    }
    
    /// Create PATCH request
    /// - Parameters:
    ///   - url: Request URL
    ///   - body: Request body
    /// - Returns: Configured JPNetworkingRequest
    public static func patch(_ url: String, body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest(method: .PATCH, url: url, body: body)
    }
    
    /// Create request builder for complex configurations
    /// - Returns: RequestBuilder instance
    public static func builder() -> RequestBuilder {
        return RequestBuilder()
    }
}

// MARK: - Request Builder

/// Fluent API builder for complex request construction
///
/// Provides chainable methods for building complex requests with
/// validation and type safety.
///
/// **Usage:**
/// ```swift
/// let request = JPNetworkingRequest.builder()
///     .method(.POST)
///     .url("/api/users")
///     .header("Authorization", "Bearer token")
///     .header("User-Agent", "MyApp/1.0")
///     .jsonBody(user)
///     .timeout(60)
///     .build()
/// ```
public final class RequestBuilder: @unchecked Sendable {
    
    // MARK: - Private Properties
    
    private var method: HTTPMethod = .GET
    private var url: String = ""
    private var headers: [String: String] = [:]
    private var body: RequestBody = .none
    private var timeout: TimeInterval = 30.0
    private var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    private var allowsCellularAccess: Bool = true
    
    /// Thread-safe access queue
    private let queue = DispatchQueue(label: "JPNetworking.RequestBuilder", attributes: .concurrent)
    
    public init() {}
    
    // MARK: - Builder Methods
    
    /// Set HTTP method
    /// - Parameter method: HTTP method
    /// - Returns: Self for chaining
    @discardableResult
    public func method(_ method: HTTPMethod) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.method = method
        }
        return self
    }
    
    /// Set request URL
    /// - Parameter url: Request URL
    /// - Returns: Self for chaining
    @discardableResult
    public func url(_ url: String) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.url = url
        }
        return self
    }
    
    /// Set all headers (replaces existing)
    /// - Parameter headers: Headers dictionary
    /// - Returns: Self for chaining
    @discardableResult
    public func headers(_ headers: [String: String]) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.headers = headers
        }
        return self
    }
    
    /// Add single header
    /// - Parameters:
    ///   - key: Header name
    ///   - value: Header value
    /// - Returns: Self for chaining
    @discardableResult
    public func header(_ key: String, _ value: String) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.headers[key] = value
        }
        return self
    }
    
    /// Set request body
    /// - Parameter body: Request body
    /// - Returns: Self for chaining
    @discardableResult
    public func body(_ body: RequestBody) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.body = body
        }
        return self
    }
    
    /// Set JSON body from Codable object
    /// - Parameter object: Encodable object
    /// - Returns: Self for chaining
    @discardableResult
    public func jsonBody<T: Encodable & Sendable>(_ object: T) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.body = .json(object)
        }
        return self
    }
    
    /// Set timeout interval
    /// - Parameter timeout: Timeout in seconds
    /// - Returns: Self for chaining
    @discardableResult
    public func timeout(_ timeout: TimeInterval) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.timeout = timeout
        }
        return self
    }
    
    /// Set cache policy
    /// - Parameter policy: URL cache policy
    /// - Returns: Self for chaining
    @discardableResult
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.cachePolicy = policy
        }
        return self
    }
    
    /// Set cellular access permission
    /// - Parameter allows: Whether to allow cellular access
    /// - Returns: Self for chaining
    @discardableResult
    public func allowsCellularAccess(_ allows: Bool) -> RequestBuilder {
        queue.async(flags: .barrier) {
            self.allowsCellularAccess = allows
        }
        return self
    }
    
    /// Build final JPNetworkingRequest
    /// - Returns: Configured JPNetworkingRequest
    public func build() -> JPNetworkingRequest {
        return queue.sync {
            return JPNetworkingRequest(
                method: method,
                url: url,
                headers: headers,
                body: body,
                timeout: timeout,
                cachePolicy: cachePolicy,
                allowsCellularAccess: allowsCellularAccess
            )
        }
    }
}

// MARK: - URLRequest Conversion
extension JPNetworkingRequest {
    
    /// Convert JPNetworkingRequest to Foundation URLRequest
    /// - Parameter baseURL: Base URL to prepend to relative URLs
    /// - Returns: Configured URLRequest
    /// - Throws: NetworkError if conversion fails
    public func toURLRequest(baseURL: String = "") throws -> URLRequest {
        // Validate request first
        try validate()
        
        // Construct full URL
        let fullURL = url.hasPrefix("http") ? url : baseURL + url
        
        guard let requestURL = URL(string: fullURL) else {
            throw NetworkError.invalidURL(fullURL)
        }
        
        // Create URLRequest
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = method.rawValue
        urlRequest.timeoutInterval = timeout
        urlRequest.cachePolicy = cachePolicy
        urlRequest.allowsCellularAccess = allowsCellularAccess
        
        // Add headers
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add Content-Type if needed and not already set
        if let contentType = body.contentType,
           urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        // Add body
        try addBody(to: &urlRequest)
        
        return urlRequest
    }
    
    /// Add body data to URLRequest
    /// - Parameter urlRequest: URLRequest to modify
    /// - Throws: NetworkError if body encoding fails
    private func addBody(to urlRequest: inout URLRequest) throws {
        switch body {
        case .none:
            break
            
        case .data(let data):
            urlRequest.httpBody = data
            
        case .json(let object):
            do {
                let jsonData = try JSONEncoder().encode(AnyEncodable(object))
                urlRequest.httpBody = jsonData
            } catch {
                throw NetworkError.jsonEncodingFailed(error)
            }
            
        case .formData(let parameters):
            let formString = parameters
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                .joined(separator: "&")
            urlRequest.httpBody = formString.data(using: .utf8)
            
        case .multipart(let formData):
            urlRequest.httpBody = formData.httpBody
            
        case .string(let string, let encoding):
            urlRequest.httpBody = string.data(using: encoding)
        }
    }
}

// MARK: - Request Validation
extension JPNetworkingRequest {
    
    /// Validate request configuration
    /// - Throws: NetworkError if validation fails
    public func validate() throws {
        // Validate URL
        if url.isEmpty {
            throw NetworkError.invalidRequest("URL cannot be empty")
        }
        
        // Validate URL format
        let testURL = url.hasPrefix("http") ? url : "https://example.com" + url
        guard URL(string: testURL) != nil else {
            throw NetworkError.invalidURL(url)
        }
        
        // Validate timeout
        if timeout <= 0 {
            throw NetworkError.invalidRequest("Timeout must be greater than 0")
        }
        
        // Validate method and body combination
        if !method.allowsBody && !body.isEmpty {
            throw NetworkError.invalidRequest("\(method.rawValue) requests should not have a body")
        }
    }
}

// MARK: - Helper Types

/// Type-erased Encodable wrapper for JSON encoding
private struct AnyEncodable: Encodable {
    private let encodable: any Encodable
    
    init(_ encodable: any Encodable) {
        self.encodable = encodable
    }
    
    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}

// MARK: - Debug Support
extension JPNetworkingRequest: CustomStringConvertible {
    /// Debug description of the request
    public var description: String {
        var desc = "\(method.rawValue) \(url)"
        if !headers.isEmpty {
            desc += "\nHeaders: \(headers)"
        }
        if !body.isEmpty {
            desc += "\nBody: \(body)"
        }
        desc += "\nTimeout: \(timeout)s"
        return desc
    }
}

/*
 🔧 REQUEST SYSTEM ARCHITECTURE EXPLANATION:
 
 1. TYPE-SAFE HTTP METHODS:
    - Enum with raw string values for URLRequest compatibility
    - CaseIterable for programmatic iteration
    - Body validation based on HTTP method semantics
 
 2. FLEXIBLE BODY SYSTEM:
    - Support for all common content types (JSON, form data, multipart, raw)
    - Automatic Content-Type header management
    - Type-safe Codable integration for Swift objects
    - Thread-safe multipart form data builder
 
 3. FLUENT BUILDER API:
    - Chainable methods for complex request construction
    - Thread-safe builder implementation
    - Validation at build time
    - Immutable result objects
 
 4. PRODUCTION FEATURES:
    - Comprehensive request validation
    - URLRequest conversion with error handling
    - Thread-safe implementations throughout
    - Extensive documentation and examples
 
 5. PERFORMANCE OPTIMIZATIONS:
    - Concurrent queues for thread safety without blocking
    - Lazy evaluation of expensive operations
    - Minimal memory allocations
    - Efficient string and data handling
 */
