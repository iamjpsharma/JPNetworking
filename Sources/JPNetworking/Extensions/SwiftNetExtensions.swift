//
//  JPNetworkingExtensions.swift
//  JPNetworking
//
//  Convenience extensions and helper methods for JPNetworking framework.
//  Provides syntactic sugar, common patterns, and developer-friendly APIs.
//

import Foundation

// MARK: - JPNetworkingRequest Extensions

extension JPNetworkingRequest {
    
    /// Add header to existing request
    /// - Parameters:
    ///   - key: Header key
    ///   - value: Header value
    /// - Returns: New request with added header
    public func adding(header key: String, value: String) -> JPNetworkingRequest {
        var newHeaders = headers
        newHeaders[key] = value
        
        return JPNetworkingRequest(
            method: method,
            url: url,
            headers: newHeaders,
            body: body,
            timeout: timeout,
            cachePolicy: cachePolicy,
            allowsCellularAccess: allowsCellularAccess
        )
    }
    
    /// Add multiple headers to existing request
    /// - Parameter headers: Headers to add
    /// - Returns: New request with added headers
    public func adding(headers: [String: String]) -> JPNetworkingRequest {
        var newHeaders = self.headers
        for (key, value) in headers {
            newHeaders[key] = value
        }
        
        return JPNetworkingRequest(
            method: method,
            url: url,
            headers: newHeaders,
            body: body,
            timeout: timeout,
            cachePolicy: cachePolicy,
            allowsCellularAccess: allowsCellularAccess
        )
    }
    
    /// Set timeout for request
    /// - Parameter timeout: Timeout interval
    /// - Returns: New request with updated timeout
    public func with(timeout: TimeInterval) -> JPNetworkingRequest {
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
    
    /// Set cache policy for request
    /// - Parameter cachePolicy: URLRequest cache policy
    /// - Returns: New request with updated cache policy
    public func with(cachePolicy: URLRequest.CachePolicy) -> JPNetworkingRequest {
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
    
    /// Set cellular access permission
    /// - Parameter allowsCellularAccess: Whether to allow cellular access
    /// - Returns: New request with updated cellular access setting
    public func with(allowsCellularAccess: Bool) -> JPNetworkingRequest {
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
    
    /// Create authenticated version of request
    /// - Parameter authProvider: Authentication provider
    /// - Returns: Authenticated request
    public func authenticated(with authProvider: AuthenticationProvider) async throws -> JPNetworkingRequest {
        return try await authProvider.authenticate(self)
    }
}

// MARK: - JPNetworkingResponse Extensions

extension JPNetworkingResponse {
    
    /// Check if response has specific status code
    /// - Parameter statusCode: Status code to check
    /// - Returns: True if response has the specified status code
    public func hasStatusCode(_ statusCode: Int) -> Bool {
        return self.statusCode == statusCode
    }
    
    /// Check if response has status code in range
    /// - Parameter range: Status code range
    /// - Returns: True if response status code is in range
    public func hasStatusCode(in range: ClosedRange<Int>) -> Bool {
        return range.contains(statusCode)
    }
    
    /// Get header value by name (case-insensitive)
    /// - Parameter name: Header name
    /// - Returns: Header value if found
    public func header(named name: String) -> String? {
        let lowercaseName = name.lowercased()
        return headers.first { $0.key.lowercased() == lowercaseName }?.value
    }
    
    /// Check if response has specific header
    /// - Parameter name: Header name
    /// - Returns: True if header exists
    public func hasHeader(named name: String) -> Bool {
        return header(named: name) != nil
    }
    
    /// Get response as string
    /// - Parameter encoding: String encoding (default: UTF-8)
    /// - Returns: Response data as string
    public func asString(encoding: String.Encoding = .utf8) -> String? {
        guard let data = data else { return nil }
        return String(data: data, encoding: encoding)
    }
    
    /// Get response as JSON dictionary
    /// - Returns: JSON dictionary if parsing succeeds
    public func asJSONDictionary() -> [String: Any]? {
        guard let data = data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    /// Get response as JSON array
    /// - Returns: JSON array if parsing succeeds
    public func asJSONArray() -> [Any]? {
        guard let data = data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }
    
    /// Decode response to different type
    /// - Parameters:
    ///   - type: Target type
    ///   - decoder: JSON decoder
    /// - Returns: Response with new type
    public func decode<U: Decodable & Sendable>(to type: U.Type, using decoder: JSONDecoder = JSONDecoder()) -> JPNetworkingResponse<U> {
        return decoded(to: type, using: decoder)
    }
    
    /// Transform response value and preserve metadata
    /// - Parameter transform: Transformation function
    /// - Returns: Transformed response
    public func mapValue<U: Sendable>(_ transform: (T) throws -> U) -> JPNetworkingResponse<U> {
        return map(transform)
    }
    
    /// Unwrap response value or throw error
    /// - Returns: Response value
    /// - Throws: NetworkError if response failed or has no value
    public func unwrap() throws -> T {
        if let error = error {
            throw error
        }
        
        guard let value = value else {
            throw NetworkError.noData
        }
        
        return value
    }
    
    /// Get response value or default
    /// - Parameter defaultValue: Default value to return if response failed
    /// - Returns: Response value or default
    public func valueOrDefault(_ defaultValue: T) -> T {
        return value ?? defaultValue
    }
}

// MARK: - NetworkManager Extensions

extension NetworkManager {
    
    /// Download file from URL
    /// - Parameters:
    ///   - url: File URL
    ///   - destinationURL: Local destination URL
    /// - Returns: Download response with file URL
    public func download(_ url: String, to destinationURL: URL) async -> JPNetworkingResponse<URL> {
        let dataResponse = await getData(url)
        
        if let data = dataResponse.data, dataResponse.isSuccess {
            do {
                try data.write(to: destinationURL)
                return JPNetworkingResponse<URL>(
                    data: dataResponse.data,
                    response: dataResponse.response,
                    request: dataResponse.request,
                    value: destinationURL,
                    error: nil
                )
            } catch {
                return JPNetworkingResponse<URL>(
                    data: dataResponse.data,
                    response: dataResponse.response,
                    request: dataResponse.request,
                    value: nil,
                    error: .customError("Failed to write file: \(error.localizedDescription)", code: nil)
                )
            }
        } else {
            return JPNetworkingResponse<URL>(
                data: dataResponse.data,
                response: dataResponse.response,
                request: dataResponse.request,
                value: nil,
                error: dataResponse.error
            )
        }
    }
    
    /// Upload file to URL
    /// - Parameters:
    ///   - fileURL: Local file URL
    ///   - url: Upload URL
    ///   - method: HTTP method (default: POST)
    ///   - headers: Additional headers
    /// - Returns: Upload response
    public func upload(
        file fileURL: URL,
        to url: String,
        method: HTTPMethod = .POST,
        headers: [String: String] = [:]
    ) async -> JPNetworkingResponse<Data> {
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            let mimeType = mimeType(for: fileURL.pathExtension)
            
            let formData = MultipartFormData()
            formData.append(fileData, withName: "file", fileName: fileName, mimeType: mimeType)
            
            let request = JPNetworkingRequest.builder()
                .method(method)
                .url(url)
                .headers(headers)
                .body(.multipart(formData))
                .build()
            
            return await execute(request, as: Data.self)
        } catch {
            return JPNetworkingResponse<Data>(
                data: nil,
                response: nil,
                request: nil,
                value: nil,
                error: .customError("Failed to read file: \(error.localizedDescription)", code: nil)
            )
        }
    }
    
    /// Get MIME type for file extension
    /// - Parameter pathExtension: File extension
    /// - Returns: MIME type string
    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        case "txt":
            return "text/plain"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - JPNetworking Static Extensions

extension JPNetworking {
    
    /// Quick JSON GET request
    /// - Parameters:
    ///   - url: Request URL
    ///   - headers: Additional headers
    /// - Returns: JSON dictionary response
    @MainActor
    public static func getJSON(
        _ url: String,
        headers: [String: String] = [:]
    ) async -> JPNetworkingResponse<[String: Any]> {
        let request = JPNetworkingRequest.builder()
            .method(.GET)
            .url(url)
            .headers(headers)
            .header("Accept", "application/json")
            .build()
        
        let dataResponse = await execute(request, as: Data.self)
        
        if let data = dataResponse.data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return JPNetworkingResponse<[String: Any]>(
                data: dataResponse.data,
                response: dataResponse.response,
                request: dataResponse.request,
                value: json,
                error: dataResponse.error
            )
        } else {
            return JPNetworkingResponse<[String: Any]>(
                data: dataResponse.data,
                response: dataResponse.response,
                request: dataResponse.request,
                value: nil,
                error: dataResponse.error ?? .jsonDecodingFailed(NSError(domain: "JPNetworking", code: -1))
            )
        }
    }
    
    /// Quick form POST request
    /// - Parameters:
    ///   - url: Request URL
    ///   - formData: Form data dictionary
    ///   - headers: Additional headers
    /// - Returns: Data response
    @MainActor
    public static func postForm(
        _ url: String,
        formData: [String: String],
        headers: [String: String] = [:]
    ) async -> JPNetworkingResponse<Data> {
        let request = JPNetworkingRequest.builder()
            .method(.POST)
            .url(url)
            .headers(headers)
            .body(.formData(formData))
            .build()
        
        return await execute(request, as: Data.self)
    }
    
    /// Quick file download
    /// - Parameters:
    ///   - url: File URL
    ///   - destinationURL: Local destination
    /// - Returns: File URL response
    @MainActor
    public static func download(_ url: String, to destinationURL: URL) async -> JPNetworkingResponse<URL> {
        return await manager.download(url, to: destinationURL)
    }
    
    /// Quick file upload
    /// - Parameters:
    ///   - fileURL: Local file URL
    ///   - url: Upload URL
    ///   - headers: Additional headers
    /// - Returns: Upload response
    @MainActor
    public static func upload(
        file fileURL: URL,
        to url: String,
        headers: [String: String] = [:]
    ) async -> JPNetworkingResponse<Data> {
        return await manager.upload(file: fileURL, to: url, headers: headers)
    }
    
    /// Ping a URL to check connectivity
    /// - Parameter url: URL to ping
    /// - Returns: True if URL is reachable
    @MainActor
    public static func ping(_ url: String) async -> Bool {
        let request = JPNetworkingRequest.builder()
            .method(.HEAD)
            .url(url)
            .timeout(5.0)
            .build()
        
        let response = await execute(request, as: Data.self)
        return response.isSuccess
    }
    
    /// Check if internet connection is available
    /// - Returns: True if internet is available
    @MainActor
    public static func isInternetAvailable() async -> Bool {
        return await ping("https://www.google.com")
    }
}

// MARK: - URL Extensions

extension URL {
    
    /// Create JPNetworking GET request for this URL
    /// - Returns: JPNetworkingRequest for GET
    public func asGETRequest() -> JPNetworkingRequest {
        return JPNetworkingRequest.get(absoluteString)
    }
    
    /// Create JPNetworking POST request for this URL
    /// - Parameter body: Request body
    /// - Returns: JPNetworkingRequest for POST
    public func asPOSTRequest(body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest.post(absoluteString, body: body)
    }
    
    /// Create JPNetworking PUT request for this URL
    /// - Parameter body: Request body
    /// - Returns: JPNetworkingRequest for PUT
    public func asPUTRequest(body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest.put(absoluteString, body: body)
    }
    
    /// Create JPNetworking DELETE request for this URL
    /// - Returns: JPNetworkingRequest for DELETE
    public func asDELETERequest() -> JPNetworkingRequest {
        return JPNetworkingRequest.delete(absoluteString)
    }
}

// MARK: - String Extensions

extension String {
    
    /// Create JPNetworking GET request for this URL string
    /// - Returns: JPNetworkingRequest for GET
    public func asGETRequest() -> JPNetworkingRequest {
        return JPNetworkingRequest.get(self)
    }
    
    /// Create JPNetworking POST request for this URL string
    /// - Parameter body: Request body
    /// - Returns: JPNetworkingRequest for POST
    public func asPOSTRequest(body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest.post(self, body: body)
    }
    
    /// Create JPNetworking PUT request for this URL string
    /// - Parameter body: Request body
    /// - Returns: JPNetworkingRequest for PUT
    public func asPUTRequest(body: RequestBody = .none) -> JPNetworkingRequest {
        return JPNetworkingRequest.put(self, body: body)
    }
    
    /// Create JPNetworking DELETE request for this URL string
    /// - Returns: JPNetworkingRequest for DELETE
    public func asDELETERequest() -> JPNetworkingRequest {
        return JPNetworkingRequest.delete(self)
    }
    
    /// URL encode string for query parameters
    /// - Returns: URL encoded string
    public func urlEncoded() -> String {
        return addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

// MARK: - Codable Extensions

extension Encodable {
    
    /// Convert to RequestBody.json
    /// - Returns: JSON request body
    public func asJSONBody() -> RequestBody {
        return .json(self)
    }
    
    /// Convert to JSON Data
    /// - Parameter encoder: JSON encoder
    /// - Returns: JSON data
    /// - Throws: Encoding error
    public func asJSONData(using encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        return try encoder.encode(self)
    }
    
    /// Convert to JSON string
    /// - Parameter encoder: JSON encoder
    /// - Returns: JSON string
    /// - Throws: Encoding error
    public func asJSONString(using encoder: JSONEncoder = JSONEncoder()) throws -> String {
        let data = try asJSONData(using: encoder)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Dictionary Extensions

extension Dictionary where Key == String, Value == String {
    
    /// Convert to form data request body
    /// - Returns: Form data request body
    public func asFormDataBody() -> RequestBody {
        return .formData(self)
    }
    
    /// Convert to query string
    /// - Returns: URL query string
    public func asQueryString() -> String {
        return map { "\($0.key.urlEncoded())=\($0.value.urlEncoded())" }
            .joined(separator: "&")
    }
}

// MARK: - Data Extensions

extension Data {
    
    /// Convert to RequestBody.data
    /// - Returns: Data request body
    public func asRequestBody() -> RequestBody {
        return .data(self)
    }
    
    /// Convert to JSON object
    /// - Returns: JSON object (dictionary or array)
    /// - Throws: JSON parsing error
    public func asJSON() throws -> Any {
        return try JSONSerialization.jsonObject(with: self)
    }
    
    /// Convert to JSON dictionary
    /// - Returns: JSON dictionary
    /// - Throws: JSON parsing error
    public func asJSONDictionary() throws -> [String: Any] {
        guard let dict = try asJSON() as? [String: Any] else {
            throw NetworkError.jsonDecodingFailed(NSError(domain: "JPNetworking", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data is not a JSON dictionary"]))
        }
        return dict
    }
    
    /// Convert to JSON array
    /// - Returns: JSON array
    /// - Throws: JSON parsing error
    public func asJSONArray() throws -> [Any] {
        guard let array = try asJSON() as? [Any] else {
            throw NetworkError.jsonDecodingFailed(NSError(domain: "JPNetworking", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data is not a JSON array"]))
        }
        return array
    }
}

/*
 🔧 EXTENSIONS ARCHITECTURE EXPLANATION:
 
 1. FLUENT API EXTENSIONS:
    - Method chaining for request building
    - Immutable transformations that return new instances
    - Convenient header and parameter manipulation
    - Type-safe conversions and transformations
 
 2. RESPONSE CONVENIENCE:
    - Easy access to common response data formats
    - Header lookup with case-insensitive matching
    - Status code checking with ranges
    - Value unwrapping and default handling
 
 3. COMMON PATTERNS:
    - File upload/download helpers
    - JSON and form data shortcuts
    - URL and string request builders
    - Connectivity checking utilities
 
 4. TYPE CONVERSIONS:
    - Codable to RequestBody
    - Data to JSON objects
    - Dictionary to query strings
    - String URL encoding
 
 5. DEVELOPER EXPERIENCE:
    - Reduces boilerplate code
    - Provides intuitive method names
    - Maintains type safety
    - Follows Swift naming conventions
 
 6. INTEGRATION:
    - Works seamlessly with core JPNetworking types
    - Preserves all framework functionality
    - Adds no performance overhead
    - Maintains thread safety
 */
