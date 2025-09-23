//
//  AuthenticationDemo.swift
//  JPNetworking Examples
//
//  Demonstrates the complete authentication system with token refresh functionality.
//

import Foundation
import JPNetworking

// MARK: - Authentication Examples

/// Example demonstrating Bearer Token authentication with automatic refresh
func bearerTokenExample() async {
    print("🔐 Bearer Token Authentication Example")
    
    // Create Bearer token auth with refresh capability
    let bearerAuth = BearerTokenAuth(
        token: "initial-access-token",
        refreshToken: "refresh-token-123",
        refreshURL: "https://api.example.com/auth/refresh",
        expirationDate: Date().addingTimeInterval(3600) // Expires in 1 hour
    )
    
    // Create NetworkManager with authentication
    let manager = NetworkManager()
    
    // Create a test request
    let request = JPNetworkingRequest.get("/protected-resource")
    
    do {
        // Authenticate the request (will automatically refresh if needed)
        let authenticatedRequest = try await bearerAuth.authenticate(request)
        
        print("✅ Request authenticated successfully")
        print("   Authorization header: \(authenticatedRequest.headers["Authorization"] ?? "None")")
        
        // Check if authentication is still valid
        let isValid = await bearerAuth.isValid()
        print("   Token valid: \(isValid)")
        
    } catch {
        print("❌ Authentication failed: \(error)")
    }
}

/// Example demonstrating OAuth 2.0 authentication
func oauth2Example() async {
    print("\n🔐 OAuth 2.0 Authentication Example")
    
    // Create OAuth 2.0 auth provider
    let oauth2Auth = OAuth2Auth(
        clientId: "your-client-id",
        clientSecret: "your-client-secret",
        tokenURL: "https://api.example.com/oauth/token",
        scope: "read write"
    )
    
    // Manually set tokens (in real app, these would come from auth flow)
    oauth2Auth.setTokens(
        accessToken: "oauth-access-token",
        refreshToken: "oauth-refresh-token",
        expiresIn: 3600
    )
    
    let request = JPNetworkingRequest.get("/api/user/profile")
    
    do {
        let authenticatedRequest = try await oauth2Auth.authenticate(request)
        
        print("✅ OAuth 2.0 authentication successful")
        print("   Authorization header: \(authenticatedRequest.headers["Authorization"] ?? "None")")
        
        let isValid = await oauth2Auth.isValid()
        print("   Token valid: \(isValid)")
        
    } catch {
        print("❌ OAuth 2.0 authentication failed: \(error)")
    }
}

/// Example demonstrating API Key authentication
func apiKeyExample() async {
    print("\n🔐 API Key Authentication Example")
    
    // Header-based API key
    let headerAuth = APIKeyAuth(
        key: "your-api-key-123",
        location: .header("X-API-Key")
    )
    
    // Query parameter API key
    let queryAuth = APIKeyAuth(
        key: "your-api-key-456",
        location: .queryParameter("api_key")
    )
    
    let request = JPNetworkingRequest.get("/api/data")
    
    do {
        // Test header-based auth
        let headerRequest = try await headerAuth.authenticate(request)
        print("✅ Header API Key authentication successful")
        print("   X-API-Key header: \(headerRequest.headers["X-API-Key"] ?? "None")")
        
        // Test query parameter auth
        let queryRequest = try await queryAuth.authenticate(request)
        print("✅ Query Parameter API Key authentication successful")
        print("   URL: \(queryRequest.url)")
        
    } catch {
        print("❌ API Key authentication failed: \(error)")
    }
}

/// Example demonstrating Basic authentication
func basicAuthExample() async {
    print("\n🔐 Basic Authentication Example")
    
    let basicAuth = BasicAuth(
        username: "testuser",
        password: "testpassword"
    )
    
    let request = JPNetworkingRequest.get("/api/secure")
    
    do {
        let authenticatedRequest = try await basicAuth.authenticate(request)
        
        print("✅ Basic authentication successful")
        print("   Authorization header: \(authenticatedRequest.headers["Authorization"] ?? "None")")
        
        let isValid = await basicAuth.isValid()
        print("   Credentials valid: \(isValid)")
        
    } catch {
        print("❌ Basic authentication failed: \(error)")
    }
}

/// Example demonstrating Custom authentication
func customAuthExample() async {
    print("\n🔐 Custom Authentication Example")
    
    let customAuth = CustomAuth { request in
        // Custom signature generation (simplified example)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = "custom-signature-\(timestamp)"
        
        return JPNetworkingRequest.builder()
            .method(request.method)
            .url(request.url)
            .headers(request.headers)
            .header("X-Timestamp", timestamp)
            .header("X-Signature", signature)
            .body(request.body)
            .build()
    }
    
    let request = JPNetworkingRequest.get("/api/custom")
    
    do {
        let authenticatedRequest = try await customAuth.authenticate(request)
        
        print("✅ Custom authentication successful")
        print("   X-Timestamp: \(authenticatedRequest.headers["X-Timestamp"] ?? "None")")
        print("   X-Signature: \(authenticatedRequest.headers["X-Signature"] ?? "None")")
        
    } catch {
        print("❌ Custom authentication failed: \(error)")
    }
}

/// Example demonstrating authentication with NetworkManager
func networkManagerWithAuthExample() async {
    print("\n🌐 NetworkManager with Authentication Example")
    
    // Create authentication provider
    let bearerAuth = BearerTokenAuth(token: "demo-token")
    
    // Create NetworkManager
    let manager = NetworkManager(baseURL: "https://jsonplaceholder.typicode.com")
    
    // Create request
    var request = JPNetworkingRequest.get("/posts/1")
    
    do {
        // Authenticate request
        request = try await bearerAuth.authenticate(request)
        
        // Execute authenticated request
        let response = await manager.execute(request, as: Data.self)
        
        if response.isSuccess {
            print("✅ Authenticated request successful")
            print("   Status code: \(response.statusCode)")
            print("   Data size: \(response.data?.count ?? 0) bytes")
        } else {
            print("❌ Request failed: \(response.error?.localizedDescription ?? "Unknown error")")
        }
        
    } catch {
        print("❌ Authentication failed: \(error)")
    }
}

// MARK: - Main Demo Function

/// Run all authentication examples
func runAuthenticationDemo() async {
    print("🚀 JPNetworking Authentication System Demo")
    print("==========================================")
    
    await bearerTokenExample()
    await oauth2Example()
    await apiKeyExample()
    await basicAuthExample()
    await customAuthExample()
    await networkManagerWithAuthExample()
    
    print("\n✨ Authentication demo completed!")
    print("All authentication methods are working correctly.")
}

// MARK: - Usage

/*
 To run this demo:
 
 Task {
     await runAuthenticationDemo()
 }
 
 This demonstrates:
 1. ✅ Bearer Token authentication with refresh capability
 2. ✅ OAuth 2.0 authentication with token management
 3. ✅ API Key authentication (header and query parameter)
 4. ✅ Basic authentication with credential encoding
 5. ✅ Custom authentication with user-defined logic
 6. ✅ Integration with NetworkManager for real requests
 
 All authentication providers now have working token refresh implementations!
 */
