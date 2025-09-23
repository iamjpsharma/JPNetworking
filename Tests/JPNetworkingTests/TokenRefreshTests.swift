//
//  TokenRefreshTests.swift
//  JPNetworkingTests
//
//  Tests for token refresh functionality in authentication providers.
//

import XCTest
@testable import JPNetworking

final class TokenRefreshTests: XCTestCase {
    
    // MARK: - Bearer Token Auth Tests
    
    func testBearerTokenAuthInitialization() {
        let bearerAuth = BearerTokenAuth(token: "test-token")
        
        Task {
            let isValid = await bearerAuth.isValid()
            XCTAssertTrue(isValid)
        }
    }
    
    func testBearerTokenAuthWithRefresh() {
        let expirationDate = Date().addingTimeInterval(3600) // 1 hour from now
        let bearerAuth = BearerTokenAuth(
            token: "initial-token",
            refreshToken: "refresh-token",
            refreshURL: "https://example.com/refresh",
            expirationDate: expirationDate
        )
        
        Task {
            let isValid = await bearerAuth.isValid()
            XCTAssertTrue(isValid)
        }
    }
    
    func testBearerTokenAuthExpiration() {
        let expiredDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let bearerAuth = BearerTokenAuth(
            token: "expired-token",
            refreshToken: "refresh-token",
            refreshURL: "https://example.com/refresh",
            expirationDate: expiredDate
        )
        
        Task {
            let isValid = await bearerAuth.isValid()
            XCTAssertFalse(isValid)
        }
    }
    
    // MARK: - OAuth2 Auth Tests
    
    func testOAuth2AuthInitialization() {
        let oauth2Auth = OAuth2Auth(
            clientId: "test-client-id",
            clientSecret: "test-client-secret",
            tokenURL: "https://example.com/token"
        )
        
        Task {
            let isValid = await oauth2Auth.isValid()
            XCTAssertFalse(isValid) // No token set initially
        }
    }
    
    func testOAuth2AuthWithTokens() {
        let oauth2Auth = OAuth2Auth(
            clientId: "test-client-id",
            clientSecret: "test-client-secret",
            tokenURL: "https://example.com/token"
        )
        
        // Set tokens manually (simulating successful auth flow)
        oauth2Auth.setTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresIn: 3600
        )
        
        Task {
            let isValid = await oauth2Auth.isValid()
            XCTAssertTrue(isValid)
        }
    }
    
    func testOAuth2AuthTokenExpiration() {
        let oauth2Auth = OAuth2Auth(
            clientId: "test-client-id",
            tokenURL: "https://example.com/token"
        )
        
        // Set expired token
        oauth2Auth.setTokens(
            accessToken: "expired-token",
            expiresIn: -3600 // Expired 1 hour ago
        )
        
        Task {
            let isValid = await oauth2Auth.isValid()
            XCTAssertFalse(isValid)
        }
    }
    
    // MARK: - API Key Auth Tests
    
    func testAPIKeyAuthHeader() {
        let apiKeyAuth = APIKeyAuth(
            key: "test-api-key",
            location: .header("X-API-Key")
        )
        
        Task {
            let isValid = await apiKeyAuth.isValid()
            XCTAssertTrue(isValid)
            
            let testRequest = JPNetworkingRequest.get("/test")
            let authenticatedRequest = try await apiKeyAuth.authenticate(testRequest)
            
            XCTAssertEqual(authenticatedRequest.headers["X-API-Key"], "test-api-key")
        }
    }
    
    func testAPIKeyAuthQueryParameter() {
        let apiKeyAuth = APIKeyAuth(
            key: "test-api-key",
            location: .queryParameter("api_key")
        )
        
        Task {
            let testRequest = JPNetworkingRequest.get("/test")
            let authenticatedRequest = try await apiKeyAuth.authenticate(testRequest)
            
            XCTAssertTrue(authenticatedRequest.url.contains("api_key=test-api-key"))
        }
    }
    
    // MARK: - Basic Auth Tests
    
    func testBasicAuthInitialization() {
        let basicAuth = BasicAuth(username: "testuser", password: "testpass")
        
        Task {
            let isValid = await basicAuth.isValid()
            XCTAssertTrue(isValid)
            
            let testRequest = JPNetworkingRequest.get("/test")
            let authenticatedRequest = try await basicAuth.authenticate(testRequest)
            
            // Verify Basic auth header is set
            XCTAssertNotNil(authenticatedRequest.headers["Authorization"])
            XCTAssertTrue(authenticatedRequest.headers["Authorization"]?.hasPrefix("Basic ") ?? false)
        }
    }
    
    func testBasicAuthEmptyCredentials() {
        let basicAuth = BasicAuth(username: "", password: "")
        
        Task {
            let isValid = await basicAuth.isValid()
            XCTAssertFalse(isValid)
        }
    }
    
    // MARK: - Custom Auth Tests
    
    func testCustomAuth() {
        let customAuth = CustomAuth { request in
            return JPNetworkingRequest.builder()
                .method(request.method)
                .url(request.url)
                .headers(request.headers)
                .header("X-Custom-Auth", "custom-signature")
                .body(request.body)
                .build()
        }
        
        Task {
            let isValid = await customAuth.isValid()
            XCTAssertTrue(isValid) // Default validator returns true
            
            let testRequest = JPNetworkingRequest.get("/test")
            let authenticatedRequest = try await customAuth.authenticate(testRequest)
            
            XCTAssertEqual(authenticatedRequest.headers["X-Custom-Auth"], "custom-signature")
        }
    }
    
    func testCustomAuthWithValidator() {
        var authValid = true
        
        let customAuth = CustomAuth(
            authenticator: { request in
                return request.adding(header: "X-Custom", value: "value")
            },
            validator: {
                return authValid
            }
        )
        
        Task {
            var isValid = await customAuth.isValid()
            XCTAssertTrue(isValid)
            
            authValid = false
            isValid = await customAuth.isValid()
            XCTAssertFalse(isValid)
        }
    }
}

// MARK: - Helper Extensions

extension JPNetworkingRequest {
    func adding(header key: String, value: String) -> JPNetworkingRequest {
        return JPNetworkingRequest.builder()
            .method(self.method)
            .url(self.url)
            .headers(self.headers)
            .header(key, value)
            .body(self.body)
            .timeout(self.timeout)
            .cachePolicy(self.cachePolicy)
            .allowsCellularAccess(self.allowsCellularAccess)
            .build()
    }
}
