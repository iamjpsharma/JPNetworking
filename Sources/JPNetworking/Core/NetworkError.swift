//
//  NetworkError.swift
//  JPNetworking
//
//  Production-ready error handling system for networking operations.
//  Provides comprehensive error categorization, user-friendly messages,
//  and programmatic error handling capabilities.
//

import Foundation

/// Comprehensive error system for JPNetworking networking operations
///
/// This enum provides detailed error categorization for all possible networking failures,
/// enabling both user-friendly error messages and programmatic error handling.
///
/// **Design Principles:**
/// - Comprehensive coverage of all networking failure scenarios
/// - User-friendly error messages via LocalizedError protocol
/// - Programmatic error codes for automated handling
/// - Clear categorization for different error types
/// - Integration with Foundation networking errors
///
/// **Usage Example:**
/// ```swift
/// let response = await JPNetworking.get("/users", as: [User].self)
/// if let error = response.error {
///     switch error {
///     case .noInternetConnection:
///         showOfflineUI()
///     case .unauthorizedAccess:
///         redirectToLogin()
///     case .jsonDecodingFailed(let underlyingError):
///         logDecodingError(underlyingError)
///     default:
///         showGenericError(error.localizedDescription)
///     }
/// }
/// ```
public enum NetworkError: Error, LocalizedError {
    
    // MARK: - Request Construction Errors
    /// URL is malformed or invalid
    case invalidURL(String)
    /// Request configuration is invalid
    case invalidRequest(String)
    /// Failed to build URLRequest from JPNetworkingRequest
    case requestBuildingFailed(String)
    
    // MARK: - Network Connectivity Errors
    /// No internet connection available
    case noInternetConnection
    /// Request timed out
    case timeout
    /// Network connection failed
    case connectionFailed(Error?)
    /// Request was cancelled by user or system
    case requestCancelled
    
    // MARK: - HTTP Status Code Errors
    /// Generic HTTP error with status code and response data
    case httpError(statusCode: Int, data: Data?)
    /// 401 Unauthorized - authentication required
    case unauthorizedAccess(statusCode: Int)
    /// 403 Forbidden - access denied
    case forbidden(statusCode: Int)
    /// 404 Not Found - resource doesn't exist
    case notFound(statusCode: Int)
    /// 5xx Server Error - server-side issues
    case serverError(statusCode: Int)
    
    // MARK: - Data Processing Errors
    /// No data received from server
    case noData
    /// Response format is invalid or unexpected
    case invalidResponse
    /// JSON decoding failed
    case jsonDecodingFailed(Error)
    /// JSON encoding failed
    case jsonEncodingFailed(Error)
    /// Response data is corrupted
    case dataCorrupted(String)
    
    // MARK: - Authentication Errors
    /// Authentication is required but not provided
    case authenticationRequired
    /// Provided credentials are invalid
    case invalidCredentials
    /// Authentication token has expired
    case tokenExpired
    /// Authentication process failed
    case authenticationFailed(String)
    
    // MARK: - Custom and Unknown Errors
    /// Custom application-specific error
    case customError(String, code: Int?)
    /// Unknown error that doesn't fit other categories
    case unknown(Error?)
    
    // MARK: - LocalizedError Implementation
    /// User-friendly error descriptions for display in UI
    public var errorDescription: String? {
        switch self {
        // Request Errors
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .requestBuildingFailed(let reason):
            return "Failed to build request: \(reason)"
            
        // Network Errors
        case .noInternetConnection:
            return "No internet connection available. Please check your network settings."
        case .timeout:
            return "Request timed out. Please try again."
        case .connectionFailed(let error):
            return "Connection failed: \(error?.localizedDescription ?? "Unknown network error")"
        case .requestCancelled:
            return "Request was cancelled"
            
        // HTTP Errors
        case .httpError(let statusCode, _):
            return "HTTP error (\(statusCode)): \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"
        case .unauthorizedAccess(let statusCode):
            return "Unauthorized access (\(statusCode)). Please check your credentials."
        case .forbidden(let statusCode):
            return "Access forbidden (\(statusCode)). You don't have permission to access this resource."
        case .notFound(let statusCode):
            return "Resource not found (\(statusCode)). The requested resource could not be found."
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
            
        // Data Errors
        case .noData:
            return "No data received from server"
        case .invalidResponse:
            return "Invalid response format received from server"
        case .jsonDecodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .jsonEncodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .dataCorrupted(let reason):
            return "Response data is corrupted: \(reason)"
            
        // Authentication Errors
        case .authenticationRequired:
            return "Authentication required. Please log in."
        case .invalidCredentials:
            return "Invalid credentials. Please check your username and password."
        case .tokenExpired:
            return "Authentication token has expired. Please log in again."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
            
        // Custom/Unknown Errors
        case .customError(let message, let code):
            return "Error \(code ?? 0): \(message)"
        case .unknown(let error):
            return "Unknown error: \(error?.localizedDescription ?? "No details available")"
        }
    }
    
    // MARK: - Error Codes for Programmatic Handling
    /// Unique error codes for programmatic error handling and logging
    public var errorCode: Int {
        switch self {
        // Request Errors (1000-1999)
        case .invalidURL: return 1001
        case .invalidRequest: return 1002
        case .requestBuildingFailed: return 1003
            
        // Network Errors (2000-2999)
        case .noInternetConnection: return 2001
        case .timeout: return 2002
        case .connectionFailed: return 2003
        case .requestCancelled: return 2004
            
        // HTTP Errors (use actual HTTP status codes)
        case .httpError(let statusCode, _): return statusCode
        case .unauthorizedAccess(let statusCode): return statusCode
        case .forbidden(let statusCode): return statusCode
        case .notFound(let statusCode): return statusCode
        case .serverError(let statusCode): return statusCode
            
        // Data Errors (3000-3999)
        case .noData: return 3001
        case .invalidResponse: return 3002
        case .jsonDecodingFailed: return 3003
        case .jsonEncodingFailed: return 3004
        case .dataCorrupted: return 3005
            
        // Authentication Errors (4000-4999)
        case .authenticationRequired: return 4001
        case .invalidCredentials: return 4002
        case .tokenExpired: return 4003
        case .authenticationFailed: return 4004
            
        // Custom/Unknown Errors (9000+)
        case .customError(_, let code): return code ?? 9999
        case .unknown: return 9000
        }
    }
    
    // MARK: - Error Category Properties
    /// Indicates if this is a network connectivity error
    public var isNetworkError: Bool {
        switch self {
        case .noInternetConnection, .timeout, .connectionFailed, .requestCancelled:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if this is an HTTP status code error
    public var isHTTPError: Bool {
        switch self {
        case .httpError, .unauthorizedAccess, .forbidden, .notFound, .serverError:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if this is an authentication-related error
    public var isAuthenticationError: Bool {
        switch self {
        case .authenticationRequired, .invalidCredentials, .tokenExpired, .authenticationFailed:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if this error suggests the user should retry the request
    public var isRetryable: Bool {
        switch self {
        case .timeout, .connectionFailed, .serverError:
            return true
        case .httpError(let statusCode, _):
            // Retry on 5xx server errors and some 4xx errors
            return statusCode >= 500 || statusCode == 408 || statusCode == 429
        default:
            return false
        }
    }
}

// MARK: - Error Factory Methods
extension NetworkError {
    
    /// Creates appropriate NetworkError from HTTP status code
    /// - Parameters:
    ///   - statusCode: HTTP status code
    ///   - data: Optional response data
    /// - Returns: Appropriate NetworkError case
    public static func fromHTTPStatusCode(_ statusCode: Int, data: Data? = nil) -> NetworkError {
        switch statusCode {
        case 401:
            return .unauthorizedAccess(statusCode: statusCode)
        case 403:
            return .forbidden(statusCode: statusCode)
        case 404:
            return .notFound(statusCode: statusCode)
        case 500...599:
            return .serverError(statusCode: statusCode)
        default:
            return .httpError(statusCode: statusCode, data: data)
        }
    }
    
    /// Creates NetworkError from URLError
    /// - Parameter error: URLError from URLSession
    /// - Returns: Appropriate NetworkError case
    public static func fromURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noInternetConnection
        case .timedOut:
            return .timeout
        case .cancelled:
            return .requestCancelled
        default:
            return .connectionFailed(error)
        }
    }
}

/*
 🚨 NETWORKERROR ARCHITECTURE EXPLANATION:
 
 1. COMPREHENSIVE ERROR COVERAGE:
    - Request construction errors (invalid URLs, malformed requests)
    - Network connectivity issues (no internet, timeouts)
    - HTTP status code errors (401, 404, 5xx, etc.)
    - Data processing errors (JSON decoding/encoding failures)
    - Authentication errors (expired tokens, invalid credentials)
    - Custom and unknown errors for edge cases
 
 2. USER-FRIENDLY ERROR MESSAGES:
    - LocalizedError protocol provides user-readable descriptions
    - Clear, actionable error messages for UI display
    - Technical details preserved for debugging
 
 3. PROGRAMMATIC ERROR HANDLING:
    - Unique error codes for automated error handling
    - Category properties (isNetworkError, isAuthenticationError)
    - Retry logic hints (isRetryable property)
 
 4. INTEGRATION WITH FOUNDATION:
    - Factory methods to convert URLError to NetworkError
    - HTTP status code mapping to appropriate error types
    - Preservation of underlying error information
 
 5. PRODUCTION CONSIDERATIONS:
    - Thread-safe enum implementation
    - No external dependencies
    - Comprehensive documentation for maintainability
    - Clear error categorization for monitoring/analytics
 */
