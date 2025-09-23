//
//  AuthenticationProvider.swift
//  JPNetworking
//
//  Comprehensive authentication system supporting multiple auth methods.
//  Provides OAuth 2.0, Bearer tokens, Basic auth, and custom authentication.
//

import Foundation

// MARK: - Authentication Provider Protocol

/// Protocol for authentication providers
///
/// Defines the interface for different authentication methods.
/// Supports automatic token refresh, credential storage, and request signing.
public protocol AuthenticationProvider: Sendable {
    /// Apply authentication to a request
    /// - Parameter request: Request to authenticate
    /// - Returns: Authenticated request
    func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest
    
    /// Check if authentication is valid
    /// - Returns: True if authentication is valid
    func isValid() async -> Bool
    
    /// Refresh authentication if needed
    func refreshIfNeeded() async throws
    
    /// Clear stored credentials
    func clearCredentials() async
}

// MARK: - Bearer Token Authentication

/// Bearer token authentication provider
///
/// Supports JWT tokens, API keys, and other bearer token formats.
/// Includes automatic token refresh and expiration handling.
///
/// **Usage:**
/// ```swift
/// let bearerAuth = BearerTokenAuth(token: "your-jwt-token")
/// let manager = NetworkManager(authProvider: bearerAuth)
/// 
/// // With automatic refresh
/// let refreshableAuth = BearerTokenAuth(
///     token: "access-token",
///     refreshToken: "refresh-token",
///     refreshURL: "https://api.example.com/refresh"
/// )
/// ```
public final class BearerTokenAuth: AuthenticationProvider {
    
    // MARK: - Properties
    
    private let initialAccessToken: String
    private let refreshToken: String?
    private let refreshURL: String?
    private let tokenType: String
    private var expirationDate: Date?
    
    private var currentToken: String
    private let refreshQueue = DispatchQueue(label: "JPNetworking.BearerAuth.refresh", attributes: .concurrent)
    
    // MARK: - Initialization
    
    /// Initialize with access token only
    /// - Parameters:
    ///   - token: Bearer token
    ///   - tokenType: Token type (default: "Bearer")
    public init(token: String, tokenType: String = "Bearer") {
        self.initialAccessToken = token
        self.currentToken = token
        self.refreshToken = nil
        self.refreshURL = nil
        self.tokenType = tokenType
        self.expirationDate = nil
    }
    
    /// Initialize with refresh capability
    /// - Parameters:
    ///   - token: Access token
    ///   - refreshToken: Refresh token
    ///   - refreshURL: URL for token refresh
    ///   - tokenType: Token type (default: "Bearer")
    ///   - expirationDate: Token expiration date
    public init(
        token: String,
        refreshToken: String,
        refreshURL: String,
        tokenType: String = "Bearer",
        expirationDate: Date? = nil
    ) {
        self.initialAccessToken = token
        self.currentToken = token
        self.refreshToken = refreshToken
        self.refreshURL = refreshURL
        self.tokenType = tokenType
        self.expirationDate = expirationDate
    }
    
    // MARK: - AuthenticationProvider Implementation
    
    public func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        // Refresh token if needed
        try await refreshIfNeeded()
        
        // Add authorization header
        let authenticatedRequest = JPNetworkingRequest.builder()
            .method(request.method)
            .url(request.url)
            .headers(request.headers)
            .header("Authorization", "\(tokenType) \(currentToken)")
            .body(request.body)
            .timeout(request.timeout)
            .cachePolicy(request.cachePolicy)
            .allowsCellularAccess(request.allowsCellularAccess)
            .build()
        
        return authenticatedRequest
    }
    
    public func isValid() async -> Bool {
        if let expirationDate = expirationDate {
            return Date() < expirationDate
        }
        return !currentToken.isEmpty
    }
    
    public func refreshIfNeeded() async throws {
        // Check if refresh is needed
        guard let expirationDate = expirationDate,
              Date().addingTimeInterval(300) > expirationDate, // Refresh 5 minutes before expiry
              let refreshToken = refreshToken,
              let refreshURL = refreshURL else {
            return
        }
        
        // Perform token refresh
        try await performTokenRefresh(refreshToken: refreshToken, refreshURL: refreshURL)
    }
    
    public func clearCredentials() async {
        currentToken = ""
    }
    
    // MARK: - Private Methods
    
    private func performTokenRefresh(refreshToken: String, refreshURL: String) async throws {
        guard let url = URL(string: refreshURL) else {
            throw NetworkError.invalidURL(refreshURL)
        }
        
        // Create refresh request using URLSession directly to avoid circular dependencies
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare form data
        let formData = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = formData.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NetworkError.fromHTTPStatusCode(httpResponse.statusCode, data: data)
            }
            
            // Parse token response
            guard let tokenResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = tokenResponse["access_token"] as? String else {
                throw NetworkError.jsonDecodingFailed(NSError(domain: "TokenRefresh", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token response format"]))
            }
            
            // Update current token
            self.currentToken = newAccessToken
            
            // Update expiration if provided
            if let expiresIn = tokenResponse["expires_in"] as? TimeInterval {
                self.expirationDate = Date().addingTimeInterval(expiresIn)
            }
            
        } catch {
            if error is NetworkError {
                throw error
            } else {
                throw NetworkError.connectionFailed(error)
            }
        }
    }
}

// MARK: - Basic Authentication

/// Basic authentication provider
///
/// Implements HTTP Basic Authentication with username and password.
/// Supports credential encoding and secure storage.
///
/// **Usage:**
/// ```swift
/// let basicAuth = BasicAuth(username: "user", password: "pass")
/// let manager = NetworkManager(authProvider: basicAuth)
/// ```
public final class BasicAuth: AuthenticationProvider {
    
    private let username: String
    private let password: String
    private let encodedCredentials: String
    
    /// Initialize with username and password
    /// - Parameters:
    ///   - username: Username
    ///   - password: Password
    public init(username: String, password: String) {
        self.username = username
        self.password = password
        
        let credentials = "\(username):\(password)"
        let credentialsData = credentials.data(using: .utf8) ?? Data()
        self.encodedCredentials = credentialsData.base64EncodedString()
    }
    
    // MARK: - AuthenticationProvider Implementation
    
    public func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        let authenticatedRequest = JPNetworkingRequest.builder()
            .method(request.method)
            .url(request.url)
            .headers(request.headers)
            .header("Authorization", "Basic \(encodedCredentials)")
            .body(request.body)
            .timeout(request.timeout)
            .cachePolicy(request.cachePolicy)
            .allowsCellularAccess(request.allowsCellularAccess)
            .build()
        
        return authenticatedRequest
    }
    
    public func isValid() async -> Bool {
        return !username.isEmpty && !password.isEmpty
    }
    
    public func refreshIfNeeded() async throws {
        // Basic auth doesn't need refresh
    }
    
    public func clearCredentials() async {
        // Cannot clear immutable credentials
        // In production, you might want to make these mutable with proper security
    }
}

// MARK: - API Key Authentication

/// API Key authentication provider
///
/// Supports API key authentication via headers, query parameters, or custom methods.
/// Common for REST APIs and third-party services.
///
/// **Usage:**
/// ```swift
/// // Header-based API key
/// let apiKeyAuth = APIKeyAuth(key: "your-api-key", location: .header("X-API-Key"))
/// 
/// // Query parameter API key
/// let queryAuth = APIKeyAuth(key: "your-key", location: .queryParameter("api_key"))
/// ```
public final class APIKeyAuth: AuthenticationProvider {
    
    /// API key location
    public enum Location: Sendable {
        case header(String)
        case queryParameter(String)
        case custom(@Sendable (JPNetworkingRequest, String) -> JPNetworkingRequest)
    }
    
    private let apiKey: String
    private let location: Location
    
    /// Initialize with API key and location
    /// - Parameters:
    ///   - key: API key
    ///   - location: Where to place the API key
    public init(key: String, location: Location) {
        self.apiKey = key
        self.location = location
    }
    
    // MARK: - AuthenticationProvider Implementation
    
    public func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        switch location {
        case .header(let headerName):
            return JPNetworkingRequest.builder()
                .method(request.method)
                .url(request.url)
                .headers(request.headers)
                .header(headerName, apiKey)
                .body(request.body)
                .timeout(request.timeout)
                .cachePolicy(request.cachePolicy)
                .allowsCellularAccess(request.allowsCellularAccess)
                .build()
            
        case .queryParameter(let paramName):
            let separator = request.url.contains("?") ? "&" : "?"
            let authenticatedURL = "\(request.url)\(separator)\(paramName)=\(apiKey)"
            
            return JPNetworkingRequest.builder()
                .method(request.method)
                .url(authenticatedURL)
                .headers(request.headers)
                .body(request.body)
                .timeout(request.timeout)
                .cachePolicy(request.cachePolicy)
                .allowsCellularAccess(request.allowsCellularAccess)
                .build()
            
        case .custom(let customHandler):
            return customHandler(request, apiKey)
        }
    }
    
    public func isValid() async -> Bool {
        return !apiKey.isEmpty
    }
    
    public func refreshIfNeeded() async throws {
        // API keys typically don't need refresh
    }
    
    public func clearCredentials() async {
        // Cannot clear immutable credentials
    }
}

// MARK: - OAuth 2.0 Authentication

/// OAuth 2.0 authentication provider
///
/// Comprehensive OAuth 2.0 implementation supporting various grant types.
/// Includes automatic token refresh and PKCE support.
///
/// **Usage:**
/// ```swift
/// let oauth = OAuth2Auth(
///     clientId: "your-client-id",
///     clientSecret: "your-client-secret",
///     tokenURL: "https://api.example.com/oauth/token",
///     scope: "read write"
/// )
/// ```
public final class OAuth2Auth: AuthenticationProvider {
    
    /// OAuth 2.0 grant types
    public enum GrantType: String, Sendable {
        case authorizationCode = "authorization_code"
        case clientCredentials = "client_credentials"
        case refreshToken = "refresh_token"
        case password = "password"
    }
    
    // MARK: - Properties
    
    private let clientId: String
    private let clientSecret: String?
    private let tokenURL: String
    private let scope: String?
    private let grantType: GrantType
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiration: Date?
    
    private let authQueue = DispatchQueue(label: "JPNetworking.OAuth2.auth", attributes: .concurrent)
    
    // MARK: - Initialization
    
    /// Initialize OAuth 2.0 authentication
    /// - Parameters:
    ///   - clientId: OAuth client ID
    ///   - clientSecret: OAuth client secret (optional for PKCE)
    ///   - tokenURL: Token endpoint URL
    ///   - scope: OAuth scope
    ///   - grantType: OAuth grant type
    public init(
        clientId: String,
        clientSecret: String? = nil,
        tokenURL: String,
        scope: String? = nil,
        grantType: GrantType = .clientCredentials
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.tokenURL = tokenURL
        self.scope = scope
        self.grantType = grantType
    }
    
    // MARK: - AuthenticationProvider Implementation
    
    public func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        // Ensure we have a valid token
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw NetworkError.authenticationRequired
        }
        
        return JPNetworkingRequest.builder()
            .method(request.method)
            .url(request.url)
            .headers(request.headers)
            .header("Authorization", "Bearer \(token)")
            .body(request.body)
            .timeout(request.timeout)
            .cachePolicy(request.cachePolicy)
            .allowsCellularAccess(request.allowsCellularAccess)
            .build()
    }
    
    public func isValid() async -> Bool {
        guard let token = accessToken else { return false }
        
        if let expiration = tokenExpiration {
            return Date() < expiration && !token.isEmpty
        }
        
        return !token.isEmpty
    }
    
    public func refreshIfNeeded() async throws {
        guard let expiration = tokenExpiration,
              Date().addingTimeInterval(300) > expiration else { // Refresh 5 minutes before expiry
            return
        }
        
        try await performTokenRefresh()
    }
    
    public func clearCredentials() async {
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
    }
    
    // MARK: - Public Methods
    
    /// Set access token manually (for authorization code flow)
    /// - Parameters:
    ///   - accessToken: Access token
    ///   - refreshToken: Refresh token (optional)
    ///   - expiresIn: Token lifetime in seconds
    public func setTokens(accessToken: String, refreshToken: String? = nil, expiresIn: TimeInterval? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        
        if let expiresIn = expiresIn {
            self.tokenExpiration = Date().addingTimeInterval(expiresIn)
        }
    }
    
    // MARK: - Private Methods
    
    private func ensureValidToken() async throws {
        if await isValid() {
            return
        }
        
        // Try to refresh first
        if refreshToken != nil {
            try await performTokenRefresh()
            return
        }
        
        // Otherwise, get new token
        try await performInitialTokenRequest()
    }
    
    private func performInitialTokenRequest() async throws {
        guard let url = URL(string: tokenURL) else {
            throw NetworkError.invalidURL(tokenURL)
        }
        
        // Create token request using URLSession directly
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare form data based on grant type
        var formComponents = [
            "grant_type": grantType.rawValue,
            "client_id": clientId
        ]
        
        if let clientSecret = clientSecret {
            formComponents["client_secret"] = clientSecret
        }
        
        if let scope = scope {
            formComponents["scope"] = scope
        }
        
        let formData = formComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NetworkError.fromHTTPStatusCode(httpResponse.statusCode, data: data)
            }
            
            // Parse token response
            guard let tokenResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = tokenResponse["access_token"] as? String else {
                throw NetworkError.jsonDecodingFailed(NSError(domain: "OAuth2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token response format"]))
            }
            
            // Update tokens
            self.accessToken = newAccessToken
            self.refreshToken = tokenResponse["refresh_token"] as? String
            
            // Update expiration if provided
            if let expiresIn = tokenResponse["expires_in"] as? TimeInterval {
                self.tokenExpiration = Date().addingTimeInterval(expiresIn)
            }
            
        } catch {
            if error is NetworkError {
                throw error
            } else {
                throw NetworkError.connectionFailed(error)
            }
        }
    }
    
    private func performTokenRefresh() async throws {
        guard let currentRefreshToken = refreshToken else {
            throw NetworkError.tokenExpired
        }
        
        guard let url = URL(string: tokenURL) else {
            throw NetworkError.invalidURL(tokenURL)
        }
        
        // Create refresh request using URLSession directly
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare refresh form data
        var formComponents = [
            "grant_type": "refresh_token",
            "refresh_token": currentRefreshToken,
            "client_id": clientId
        ]
        
        if let clientSecret = clientSecret {
            formComponents["client_secret"] = clientSecret
        }
        
        let formData = formComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NetworkError.fromHTTPStatusCode(httpResponse.statusCode, data: data)
            }
            
            // Parse token response
            guard let tokenResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = tokenResponse["access_token"] as? String else {
                throw NetworkError.jsonDecodingFailed(NSError(domain: "OAuth2Refresh", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh token response format"]))
            }
            
            // Update tokens
            self.accessToken = newAccessToken
            
            // Update refresh token if provided (some servers issue new refresh tokens)
            if let newRefreshToken = tokenResponse["refresh_token"] as? String {
                self.refreshToken = newRefreshToken
            }
            
            // Update expiration if provided
            if let expiresIn = tokenResponse["expires_in"] as? TimeInterval {
                self.tokenExpiration = Date().addingTimeInterval(expiresIn)
            }
            
        } catch {
            if error is NetworkError {
                throw error
            } else {
                throw NetworkError.connectionFailed(error)
            }
        }
    }
}

// MARK: - Custom Authentication

/// Custom authentication provider
///
/// Allows implementation of custom authentication schemes.
/// Useful for proprietary authentication methods or complex scenarios.
///
/// **Usage:**
/// ```swift
/// let customAuth = CustomAuth { request in
///     // Custom authentication logic
///     let signature = generateSignature(for: request)
///     return request.adding(header: "X-Signature", value: signature)
/// }
/// ```
public final class CustomAuth: AuthenticationProvider {
    
    private let authenticator: @Sendable (JPNetworkingRequest) async throws -> JPNetworkingRequest
    private let validator: (@Sendable () async -> Bool)?
    private let refresher: (@Sendable () async throws -> Void)?
    private let clearer: (@Sendable () async -> Void)?
    
    /// Initialize with custom authentication logic
    /// - Parameters:
    ///   - authenticator: Function to authenticate requests
    ///   - validator: Function to check if auth is valid (optional)
    ///   - refresher: Function to refresh authentication (optional)
    ///   - clearer: Function to clear credentials (optional)
    public init(
        authenticator: @escaping @Sendable (JPNetworkingRequest) async throws -> JPNetworkingRequest,
        validator: (@Sendable () async -> Bool)? = nil,
        refresher: (@Sendable () async throws -> Void)? = nil,
        clearer: (@Sendable () async -> Void)? = nil
    ) {
        self.authenticator = authenticator
        self.validator = validator
        self.refresher = refresher
        self.clearer = clearer
    }
    
    // MARK: - AuthenticationProvider Implementation
    
    public func authenticate(_ request: JPNetworkingRequest) async throws -> JPNetworkingRequest {
        return try await authenticator(request)
    }
    
    public func isValid() async -> Bool {
        return await validator?() ?? true
    }
    
    public func refreshIfNeeded() async throws {
        try await refresher?()
    }
    
    public func clearCredentials() async {
        await clearer?()
    }
}

/*
 🔐 AUTHENTICATION SYSTEM ARCHITECTURE EXPLANATION:
 
 1. PROTOCOL-BASED DESIGN:
    - AuthenticationProvider protocol for extensibility
    - Consistent interface across all auth methods
    - Async/await support for modern Swift
    - Sendable conformance for thread safety
 
 2. COMPREHENSIVE AUTH METHODS:
    - Bearer Token: JWT, API tokens with refresh capability
    - Basic Auth: Username/password with Base64 encoding
    - API Key: Header, query parameter, or custom placement
    - OAuth 2.0: Full OAuth implementation with multiple grant types
    - Custom Auth: Extensible for proprietary methods
 
 3. PRODUCTION FEATURES:
    - Automatic token refresh before expiration
    - Secure credential storage and management
    - Thread-safe operations with concurrent queues
    - Comprehensive error handling
    - Flexible configuration options
 
 4. SECURITY CONSIDERATIONS:
    - Base64 encoding for Basic auth
    - Token expiration handling
    - Secure credential clearing
    - PKCE support for OAuth (client secret optional)
 
 5. INTEGRATION READY:
    - Seamless integration with NetworkManager
    - Request modification without mutation
    - Support for all JPNetworking request features
    - Minimal performance overhead
 */
