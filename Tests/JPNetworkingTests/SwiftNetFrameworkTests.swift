//
//  JPNetworkingFrameworkTests.swift
//  JPNetworkingTests
//
//  Comprehensive tests for JPNetworking framework functionality.
//  Tests core components, error handling, and integration scenarios.
//

import XCTest
@testable import JPNetworking

final class JPNetworkingFrameworkTests: XCTestCase {
    
    // MARK: - Test Models
    
    struct TestUser: Codable, Sendable, Equatable {
        let id: Int
        let name: String
        let email: String
    }
    
    struct TestPost: Codable, Sendable, Equatable {
        let id: Int
        let title: String
        let body: String
        let userId: Int
    }
    
    // MARK: - Framework Information Tests
    
    @MainActor
    func testFrameworkInfo() {
        let info = JPNetworking.frameworkInfo()
        
        XCTAssertEqual(info["name"] as? String, "JPNetworking")
        XCTAssertEqual(info["version"] as? String, "1.0.0")
        XCTAssertNotNil(info["buildInfo"])
        XCTAssertEqual(info["swiftVersion"] as? String, "5.7+")
        
        let platforms = info["platforms"] as? [String]
        XCTAssertNotNil(platforms)
        XCTAssertTrue(platforms?.contains("iOS 13.0+") ?? false)
        
        let features = info["features"] as? [String]
        XCTAssertNotNil(features)
        XCTAssertTrue(features?.contains("Async/Await Support") ?? false)
    }
    
    @MainActor
    func testFrameworkInfoPrint() {
        // Test that printing framework info doesn't crash
        JPNetworking.printFrameworkInfo()
    }
    
    // MARK: - Request Building Tests
    
    func testSimpleRequestCreation() {
        let request = JPNetworkingRequest.get("/users")
        
        XCTAssertEqual(request.method, .GET)
        XCTAssertEqual(request.url, "/users")
        XCTAssertTrue(request.headers.isEmpty)
        XCTAssertEqual(request.timeout, 30.0)
    }
    
    func testRequestBuilderPattern() {
        let testUser = TestUser(id: 1, name: "Test User", email: "test@example.com")
        
        let request = JPNetworkingRequest.builder()
            .method(.POST)
            .url("/users")
            .header("Authorization", "Bearer token123")
            .header("Content-Type", "application/json")
            .jsonBody(testUser)
            .timeout(60)
            .build()
        
        XCTAssertEqual(request.method, .POST)
        XCTAssertEqual(request.url, "/users")
        XCTAssertEqual(request.headers["Authorization"], "Bearer token123")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.timeout, 60)
    }
    
    func testHTTPMethodProperties() {
        XCTAssertTrue(HTTPMethod.POST.allowsBody)
        XCTAssertTrue(HTTPMethod.PUT.allowsBody)
        XCTAssertTrue(HTTPMethod.PATCH.allowsBody)
        
        XCTAssertFalse(HTTPMethod.GET.allowsBody)
        XCTAssertFalse(HTTPMethod.DELETE.allowsBody)
        XCTAssertFalse(HTTPMethod.HEAD.allowsBody)
    }
    
    func testRequestValidation() {
        // Test empty URL validation
        let emptyURLRequest = JPNetworkingRequest(method: .GET, url: "")
        XCTAssertThrowsError(try emptyURLRequest.validate()) { error in
            if case NetworkError.invalidRequest(let message) = error {
                XCTAssertTrue(message.contains("URL cannot be empty"))
            } else {
                XCTFail("Expected invalidRequest error")
            }
        }
        
        // Test invalid timeout
        let invalidTimeoutRequest = JPNetworkingRequest(method: .GET, url: "/test", timeout: -1)
        XCTAssertThrowsError(try invalidTimeoutRequest.validate()) { error in
            if case NetworkError.invalidRequest(let message) = error {
                XCTAssertTrue(message.contains("Timeout must be greater than 0"))
            } else {
                XCTFail("Expected invalidRequest error")
            }
        }
    }
    
    // MARK: - Request Body Tests
    
    func testRequestBodyTypes() {
        // Test empty body
        XCTAssertTrue(RequestBody.none.isEmpty)
        XCTAssertNil(RequestBody.none.contentType)
        
        // Test data body
        let data = "test".data(using: .utf8)!
        let dataBody = RequestBody.data(data)
        XCTAssertFalse(dataBody.isEmpty)
        XCTAssertEqual(dataBody.contentType, "application/octet-stream")
        
        // Test string body
        let stringBody = RequestBody.string("test")
        XCTAssertFalse(stringBody.isEmpty)
        XCTAssertEqual(stringBody.contentType, "text/plain; charset=utf-8")
        
        // Test form data body
        let formBody = RequestBody.formData(["key": "value"])
        XCTAssertFalse(formBody.isEmpty)
        XCTAssertEqual(formBody.contentType, "application/x-www-form-urlencoded; charset=utf-8")
    }
    
    func testMultipartFormData() {
        let formData = MultipartFormData()
        
        // Test adding string field
        formData.append("John Doe", withName: "name")
        
        // Test adding data field
        let imageData = "fake image data".data(using: .utf8)!
        formData.append(imageData, withName: "avatar", fileName: "profile.jpg", mimeType: "image/jpeg")
        
        let httpBody = formData.httpBody
        XCTAssertFalse(httpBody.isEmpty)
        
        let bodyString = String(data: httpBody, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("name=\"name\""))
        XCTAssertTrue(bodyString.contains("John Doe"))
        XCTAssertTrue(bodyString.contains("name=\"avatar\""))
        XCTAssertTrue(bodyString.contains("filename=\"profile.jpg\""))
        XCTAssertTrue(bodyString.contains("Content-Type: image/jpeg"))
    }
    
    // MARK: - Response Tests
    
    func testResponseCreation() {
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
        XCTAssertFalse(response.isFailure)
        XCTAssertEqual(response.value, testUser)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.statusCode, 200)
    }
    
    func testResponseStatusCodeCategories() {
        // Test success response
        let successResponse: JPNetworkingResponse<String> = createMockResponse(statusCode: 200)
        XCTAssertTrue(successResponse.isSuccess)
        XCTAssertFalse(successResponse.isClientError)
        XCTAssertFalse(successResponse.isServerError)
        
        // Test client error response
        let clientErrorResponse: JPNetworkingResponse<String> = createMockResponse(statusCode: 404)
        XCTAssertFalse(clientErrorResponse.isSuccess)
        XCTAssertTrue(clientErrorResponse.isClientError)
        XCTAssertFalse(clientErrorResponse.isServerError)
        
        // Test server error response
        let serverErrorResponse: JPNetworkingResponse<String> = createMockResponse(statusCode: 500)
        XCTAssertFalse(serverErrorResponse.isSuccess)
        XCTAssertFalse(serverErrorResponse.isClientError)
        XCTAssertTrue(serverErrorResponse.isServerError)
        
        // Test informational response
        let infoResponse: JPNetworkingResponse<String> = createMockResponse(statusCode: 100)
        XCTAssertTrue(infoResponse.isInformational)
        
        // Test redirect response
        let redirectResponse: JPNetworkingResponse<String> = createMockResponse(statusCode: 302)
        XCTAssertTrue(redirectResponse.isRedirect)
    }
    
    func testResponseMapping() {
        let testUser = TestUser(id: 1, name: "Test User", email: "test@example.com")
        
        // Create mock HTTP response with 200 status
        let url = URL(string: "https://api.example.com/test")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        
        let userResponse = JPNetworkingResponse<TestUser>(
            data: nil,
            response: httpResponse,
            request: nil,
            value: testUser,
            error: nil
        )
        
        // Test successful mapping
        let nameResponse = userResponse.map { user in
            return user.name
        }
        
        XCTAssertTrue(nameResponse.isSuccess)
        XCTAssertEqual(nameResponse.value, "Test User")
        XCTAssertNil(nameResponse.error)
    }
    
    func testResponseBuilder() {
        let testUser = TestUser(id: 1, name: "Test User", email: "test@example.com")
        
        // Create mock HTTP response for success builder
        let url = URL(string: "https://api.example.com/test")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        
        // Test success builder
        let successResponse = ResponseBuilder.success(value: testUser, response: httpResponse)
        XCTAssertTrue(successResponse.isSuccess)
        XCTAssertEqual(successResponse.value, testUser)
        XCTAssertNil(successResponse.error)
        
        // Test failure builder
        let failureResponse: JPNetworkingResponse<TestUser> = ResponseBuilder.failure(error: .noInternetConnection)
        XCTAssertTrue(failureResponse.isFailure)
        XCTAssertNil(failureResponse.value)
        if let error = failureResponse.error {
            XCTAssertTrue(areEqual(error, .noInternetConnection))
        } else {
            XCTFail("Expected error to be present")
        }
    }
    
    // MARK: - Error Tests
    
    func testNetworkErrorCategories() {
        // Test network errors
        XCTAssertTrue(NetworkError.noInternetConnection.isNetworkError)
        XCTAssertTrue(NetworkError.timeout.isNetworkError)
        XCTAssertTrue(NetworkError.connectionFailed(nil).isNetworkError)
        
        // Test HTTP errors
        XCTAssertTrue(NetworkError.unauthorizedAccess(statusCode: 401).isHTTPError)
        XCTAssertTrue(NetworkError.notFound(statusCode: 404).isHTTPError)
        XCTAssertTrue(NetworkError.serverError(statusCode: 500).isHTTPError)
        
        // Test authentication errors
        XCTAssertTrue(NetworkError.authenticationRequired.isAuthenticationError)
        XCTAssertTrue(NetworkError.invalidCredentials.isAuthenticationError)
        XCTAssertTrue(NetworkError.tokenExpired.isAuthenticationError)
    }
    
    func testNetworkErrorRetryability() {
        // Test retryable errors
        XCTAssertTrue(NetworkError.timeout.isRetryable)
        XCTAssertTrue(NetworkError.connectionFailed(nil).isRetryable)
        XCTAssertTrue(NetworkError.serverError(statusCode: 500).isRetryable)
        
        // Test non-retryable errors
        XCTAssertFalse(NetworkError.invalidURL("").isRetryable)
        XCTAssertFalse(NetworkError.unauthorizedAccess(statusCode: 401).isRetryable)
        XCTAssertFalse(NetworkError.jsonDecodingFailed(NSError()).isRetryable)
    }
    
    func testNetworkErrorCodes() {
        XCTAssertEqual(NetworkError.invalidURL("").errorCode, 1001)
        XCTAssertEqual(NetworkError.noInternetConnection.errorCode, 2001)
        XCTAssertEqual(NetworkError.unauthorizedAccess(statusCode: 401).errorCode, 401)
        XCTAssertEqual(NetworkError.noData.errorCode, 3001)
        XCTAssertEqual(NetworkError.authenticationRequired.errorCode, 4001)
    }
    
    func testNetworkErrorFromHTTPStatusCode() {
        let error401 = NetworkError.fromHTTPStatusCode(401)
        if case .unauthorizedAccess(let statusCode) = error401 {
            XCTAssertEqual(statusCode, 401)
        } else {
            XCTFail("Expected unauthorizedAccess error")
        }
        
        let error500 = NetworkError.fromHTTPStatusCode(500)
        if case .serverError(let statusCode) = error500 {
            XCTAssertEqual(statusCode, 500)
        } else {
            XCTFail("Expected serverError error")
        }
    }
    
    // MARK: - Configuration Tests
    
    func testNetworkConfiguration() {
        let config = NetworkConfiguration(
            baseURL: "https://api.example.com",
            defaultHeaders: ["Authorization": "Bearer token"],
            timeout: 60.0,
            allowsCellularAccess: false
        )
        
        XCTAssertEqual(config.baseURL, "https://api.example.com")
        XCTAssertEqual(config.defaultHeaders["Authorization"], "Bearer token")
        XCTAssertEqual(config.timeout, 60.0)
        XCTAssertFalse(config.allowsCellularAccess)
    }
    
    @MainActor
    func testNetworkManagerConfiguration() {
        let config = NetworkConfiguration(
            baseURL: "https://api.example.com",
            defaultHeaders: ["User-Agent": "TestApp/1.0"]
        )
        
        let manager = NetworkManager(configuration: config)
        XCTAssertEqual(manager.configuration.baseURL, "https://api.example.com")
        XCTAssertEqual(manager.configuration.defaultHeaders["User-Agent"], "TestApp/1.0")
    }
    
    // MARK: - Helper Methods
    
    private func createMockResponse<T>(statusCode: Int) -> JPNetworkingResponse<T> {
        let url = URL(string: "https://api.example.com/test")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
        
        return JPNetworkingResponse<T>(
            data: nil,
            response: httpResponse,
            request: nil,
            value: nil,
            error: nil
        )
    }
}

// MARK: - Test Helper Functions

/// Helper function to compare NetworkError cases for testing
private func areEqual(_ lhs: NetworkError, _ rhs: NetworkError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidURL(let lhsURL), .invalidURL(let rhsURL)):
        return lhsURL == rhsURL
    case (.noInternetConnection, .noInternetConnection),
         (.timeout, .timeout),
         (.requestCancelled, .requestCancelled),
         (.noData, .noData),
         (.invalidResponse, .invalidResponse),
         (.authenticationRequired, .authenticationRequired),
         (.invalidCredentials, .invalidCredentials),
         (.tokenExpired, .tokenExpired):
        return true
    case (.unauthorizedAccess(let lhsCode), .unauthorizedAccess(let rhsCode)),
         (.forbidden(let lhsCode), .forbidden(let rhsCode)),
         (.notFound(let lhsCode), .notFound(let rhsCode)),
         (.serverError(let lhsCode), .serverError(let rhsCode)):
        return lhsCode == rhsCode
    default:
        return false
    }
}
