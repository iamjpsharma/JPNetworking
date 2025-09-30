# JPNetworking - Advanced Swift Networking Framework

[![Swift Version](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/iamjpsharma/JPNetworking)

A modern, production-ready networking framework for Swift that rivals AFNetworking and Alamofire. Built with modern Swift concurrency, type safety, and developer experience in mind.

## 🌟 Key Features

- ✅ **Modern Swift Concurrency** - Full async/await support with structured concurrency
- ✅ **Type-Safe API** - Generic responses with compile-time type checking
- ✅ **Fluent Request Building** - Chainable API for complex request construction
- ✅ **Comprehensive Error Handling** - Detailed error categorization and user-friendly messages
- ✅ **Automatic JSON Handling** - Seamless Codable integration for encoding/decoding
- ✅ **Advanced Caching System** - Multi-level caching with TTL, compression, and intelligent eviction
- ✅ **Intelligent Retry Logic** - Exponential backoff, jitter, and configurable retry policies
- ✅ **Thread-Safe Design** - Safe concurrent access throughout the framework
- ✅ **Zero Dependencies** - Pure Swift/Foundation implementation
- ✅ **Production Ready** - Extensive testing, documentation, and real-world usage

## 📱 Platform Support

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 13.0+          |
| macOS    | 10.15+         |
| tvOS     | 13.0+          |
| watchOS  | 6.0+           |

## 🚀 Quick Start

### 📦 Installation

### Swift Package Manager

Add JPNetworking to your project using Xcode or by adding it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/iamjpsharma/JPNetworking.git", from: "1.0.0")
]
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'JPNetworking', '~> 1.0'
```

### Basic Usage

```swift
import JPNetworking

// Define your data models
struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

// Simple GET request with async/await
let response = await JPNetworking.get("https://api.example.com/users/1", as: User.self)
if response.isSuccess, let user = response.value {
    print("User: \(user.name)")
} else if let error = response.error {
    print("Error: \(error.localizedDescription)")
}
```

### Configuration

```swift
// Configure base URL and default headers
JPNetworking.configure(
    baseURL: "https://api.myapp.com",
    defaultHeaders: [
        "Authorization": "Bearer \(authToken)",
        "User-Agent": "MyApp/1.0",
        "Accept": "application/json"
    ],
    timeout: 30.0
)

// Now use relative URLs
let users = await JPNetworking.get("/users", as: [User].self)
```

## 📖 Comprehensive Usage Guide

### 1. Making Requests

#### GET Requests
```swift
// Simple GET
let users = await JPNetworking.get("/users", as: [User].self)

// GET with custom decoder
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let events = await JPNetworking.get("/events", as: [Event].self, decoder: decoder)
```

#### POST Requests
```swift
struct CreateUser: Codable {
    let name: String
    let email: String
}

let newUser = CreateUser(name: "John Doe", email: "john@example.com")
let response = await JPNetworking.post("/users", body: newUser, as: User.self)
```

#### PUT/PATCH/DELETE Requests
```swift
// PUT request
let updatedUser = await JPNetworking.put("/users/123", body: userUpdate, as: User.self)

// PATCH request
let patchedUser = await JPNetworking.patch("/users/123", body: partialUpdate, as: User.self)

// DELETE request
let deleteResponse = await JPNetworking.delete("/users/123", as: DeleteResponse.self)
```

### 2. Advanced Request Building

```swift
let request = JPNetworkingRequest.builder()
    .method(.POST)
    .url("/api/posts")
    .header("Authorization", "Bearer \(token)")
    .header("Content-Type", "application/json")
    .jsonBody(newPost)
    .timeout(60)
    .cachePolicy(.reloadIgnoringLocalCacheData)
    .build()

let response = await JPNetworking.execute(request, as: Post.self)
```

### 3. File Uploads with Multipart

```swift
let formData = MultipartFormData()
formData.append(imageData, withName: "avatar", fileName: "profile.jpg", mimeType: "image/jpeg")
formData.append("John Doe", withName: "name")
formData.append("john@example.com", withName: "email")

let request = JPNetworkingRequest.post("/upload", body: .multipart(formData))
let response = await JPNetworking.execute(request, as: UploadResponse.self)
```

### 4. Error Handling

```swift
let response = await JPNetworking.get("/users", as: [User].self)

switch response.error {
case .none:
    // Success - use response.value
    if let users = response.value {
        updateUI(with: users)
    }
    
case .noInternetConnection:
    showOfflineMessage()
    
case .unauthorizedAccess:
    redirectToLogin()
    
case .jsonDecodingFailed(let error):
    logDecodingError(error)
    
case .serverError(let statusCode):
    showServerError(statusCode)
    
default:
    showGenericError(response.error?.localizedDescription ?? "Unknown error")
}
```

### 5. Response Transformation

```swift
// Transform response data
let userResponse = await JPNetworking.get("/user/123", as: User.self)
let viewModelResponse = userResponse.map { user in
    UserViewModel(user: user)
}

// Chain multiple transformations
let profileResponse = userResponse.flatMap { user in
    return await JPNetworking.get("/users/\(user.id)/profile", as: UserProfile.self)
}
```

### 6. Batch Operations

```swift
let requests = [
    JPNetworkingRequest.get("/users"),
    JPNetworkingRequest.get("/posts"),
    JPNetworkingRequest.get("/comments")
]

let responses = await JPNetworking.executeAll(requests)
// All requests execute concurrently
```

### 7. Completion Handler API (Legacy Support)

```swift
JPNetworking.get("/users", as: [User].self) { response in
    DispatchQueue.main.async {
        if response.isSuccess, let users = response.value {
            self.updateUI(with: users)
        } else {
            self.showError(response.error)
        }
    }
}
```

### 8. Advanced Caching

```swift
// Configure global caching
JPNetworking.configure(
    baseURL: "https://api.myapp.com",
    defaultHeaders: ["Authorization": "Bearer \(token)"]
)

// Use different cache policies per request
let userProfile = await JPNetworking.get(
    "/profile", 
    as: UserProfile.self,
    cachePolicy: .cacheFirst // Use cache if available
)

let realTimeData = await JPNetworking.get(
    "/live-data", 
    as: LiveData.self,
    cachePolicy: .networkOnly // Always fetch fresh data
)

// Custom cache configuration
let cacheConfig = CacheConfiguration(
    memoryCapacity: 50 * 1024 * 1024, // 50MB
    diskCapacity: 200 * 1024 * 1024,  // 200MB
    defaultTTL: 600, // 10 minutes
    strategy: .memoryAndDisk,
    compressionEnabled: true
)
```

### 9. Intelligent Retry Logic

```swift
// Configure retry behavior
let retryConfig = RetryConfiguration(
    maxRetries: 3,
    backoffStrategy: .exponential(base: 1.0, cap: 30.0),
    jitterStrategy: .equal,
    retryableStatusCodes: [408, 429, 500, 502, 503, 504]
)

let response = await JPNetworking.get(
    "/important-data",
    as: ImportantData.self,
    retryConfiguration: retryConfig
)

// Use preset retry configurations
let criticalResponse = await JPNetworking.get(
    "/critical-endpoint",
    as: CriticalData.self,
    retryConfiguration: .aggressive // 5 retries with longer timeouts
)
```

### 10. Cache Policies

```swift
// Different cache policies for different use cases
let staticData = await JPNetworking.get("/config", as: Config.self, cachePolicy: .staticData)
let realTimeData = await JPNetworking.get("/prices", as: Prices.self, cachePolicy: .realTime)
let offlineData = await JPNetworking.get("/cached", as: Data.self, cachePolicy: .offlineFirst)

// Custom cache policy
let customPolicy = CachePolicy.custom(shouldReadFromCache: true, shouldWriteToCache: false)
let response = await JPNetworking.get("/data", as: Data.self, cachePolicy: customPolicy)
```

### 11. Authentication Support

```swift
// Bearer Token Authentication
let bearerAuth = BearerTokenAuth(token: "your-jwt-token")
let authenticatedRequest = try await bearerAuth.authenticate(request)

// Basic Authentication
let basicAuth = BasicAuth(username: "user", password: "pass")

// API Key Authentication
let apiKeyAuth = APIKeyAuth(key: "your-key", location: .header("X-API-Key"))

// OAuth 2.0 Authentication
let oauth = OAuth2Auth(
    clientId: "client-id",
    clientSecret: "client-secret",
    tokenURL: "https://api.example.com/oauth/token"
)
oauth.setTokens(accessToken: "access-token", refreshToken: "refresh-token")

// Custom Authentication
let customAuth = CustomAuth { request in
    return request.adding(header: "X-Signature", value: generateSignature(for: request))
}
```

### 12. Request/Response Interceptors

```swift
// Add logging interceptor
let loggingInterceptor = LoggingRequestInterceptor(logLevel: .detailed)
await InterceptorManager.shared.addRequestInterceptor(loggingInterceptor)

// Add User-Agent interceptor
let userAgentInterceptor = UserAgentInterceptor(userAgent: "MyApp/1.0")
await InterceptorManager.shared.addRequestInterceptor(userAgentInterceptor)

// Add response error handling
let errorInterceptor = ErrorHandlingInterceptor { error, request in
    if case .unauthorizedAccess = error {
        await redirectToLogin()
    }
}
await InterceptorManager.shared.addResponseInterceptor(errorInterceptor)

// Custom request validation
let validationInterceptor = RequestValidationInterceptor(validators: [
    { request in
        guard !request.url.isEmpty else {
            throw NetworkError.invalidURL("URL cannot be empty")
        }
    }
])
```

### 13. Advanced Logging

```swift
// Configure logging
await JPNetworkingLogger.shared.setEnabled(true)
await JPNetworkingLogger.shared.addDestination(ConsoleLogDestination(minimumLogLevel: .debug))

// File logging with rotation
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let logFileURL = documentsURL.appendingPathComponent("swiftnet.log")
let fileDestination = FileLogDestination(fileURL: logFileURL, minimumLogLevel: .info)
await JPNetworkingLogger.shared.addDestination(fileDestination)

// OS Log integration (iOS 14+)
if #available(iOS 14.0, *) {
    let osLogDestination = OSLogDestination(subsystem: "com.myapp", category: "networking")
    await JPNetworkingLogger.shared.addDestination(osLogDestination)
}

// Use logging in your code
JPNetworkingInfo("Starting network request", metadata: ["url": "/api/users"])
JPNetworkingError("Network request failed", metadata: ["error": error.localizedDescription])
```

### 14. Convenience Extensions

```swift
// Request extensions
let request = JPNetworkingRequest.get("/users")
    .adding(header: "Authorization", value: "Bearer token")
    .with(timeout: 60.0)
    .with(allowsCellularAccess: false)

// Response extensions
let response = await JPNetworking.get("/users", as: [User].self)
if response.hasStatusCode(in: 200...299) {
    let userAgent = response.header(named: "User-Agent")
    let jsonString = response.asString()
}

// String and URL extensions
let request1 = "https://api.example.com/users".asGETRequest()
let request2 = URL(string: "https://api.example.com")!.asPOSTRequest(body: user.asJSONBody())

// Data and Dictionary extensions
let formData = ["key": "value"].asFormDataBody()
let queryString = ["param1": "value1", "param2": "value2"].asQueryString()
```

### 15. Network Reachability

```swift
// Monitor network status
let reachability = NetworkReachabilityManager.shared

// Start listening for network changes
await reachability.startListening { status in
    switch status {
    case .reachable(.ethernetOrWiFi):
        print("Connected via WiFi/Ethernet")
    case .reachable(.cellular):
        print("Connected via Cellular")
    case .notReachable:
        print("No network connection")
    case .unknown:
        print("Network status unknown")
    }
}

// Check specific host reachability
let isReachable = await reachability.isReachable(url: "https://api.example.com")

// Enable automatic request queueing when offline
await reachability.setRequestQueueing(enabled: true)

// Wait for network to become available
let networkAvailable = await reachability.waitForReachability(timeout: 30.0)
```

### 16. Background Downloads & Uploads

```swift
// Background download with progress tracking
let taskManager = BackgroundTaskManager.shared

let downloadTask = await taskManager.download(
    from: "https://example.com/largefile.zip",
    to: documentsURL.appendingPathComponent("largefile.zip")
)

downloadTask.progressHandler = { progress in
    print("Download: \(progress.fractionCompleted * 100)%")
    print("Speed: \(progress.formattedBytesPerSecond)")
    print("ETA: \(progress.formattedETA)")
}

downloadTask.completionHandler = { status in
    switch status {
    case .completed(let fileURL):
        print("Downloaded to: \(fileURL)")
    case .failed(let error):
        print("Download failed: \(error)")
    default:
        break
    }
}

// Background upload
let uploadTask = await taskManager.upload(
    file: localFileURL,
    to: "https://api.example.com/upload"
)
```

### 17. SSL Certificate Pinning

```swift
// Load certificates from app bundle
let certificates = SSLPinningManager.certificates(in: Bundle.main)

// Create SSL security policy
let sslPolicy = SSLSecurityPolicy.certificatePinning(certificates: certificates)

// Initialize SSL pinning manager
let sslManager = SSLPinningManager(policy: sslPolicy)

// Create NetworkManager with SSL pinning
let secureManager = NetworkManager(sslPinningManager: sslManager)

// Public key pinning (more flexible)
let publicKeys = certificates.compactMap { SSLPinningManager.publicKey(from: $0) }
let keyPinningPolicy = SSLSecurityPolicy.publicKeyPinning(publicKeys: Set(publicKeys))

// Development mode (allows invalid certificates)
let devPolicy = SSLSecurityPolicy.development
```

### 18. Advanced Response Serialization

```swift
// JSON serialization with custom decoder
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let jsonResponse = await JPNetworking.get("/users", as: Data.self)
    .asJSON([User].self, decoder: decoder)

// XML serialization
let xmlResponse = await JPNetworking.get("/data.xml", as: Data.self)
    .asXML()

// String serialization with encoding
let textResponse = await JPNetworking.get("/readme.txt", as: Data.self)
    .asString(encoding: .utf8)

// Image serialization
let imageResponse = await JPNetworking.get("/photo.jpg", as: Data.self)
    .asImage(scale: 2.0)

// Custom serialization
let customSerializer = CustomResponseSerializer<MyCustomType> { data, response in
    // Custom parsing logic
    return try MyCustomType.parse(from: data)
}

let customResponse = dataResponse.serialized(using: customSerializer)
```

### 19. Network Activity Indicator

```swift
// Enable automatic activity indicator management
await JPNetworking.configureActivityIndicator(
    enabled: true,
    activationDelay: 0.1,
    deactivationDelay: 0.1
) { isActive in
    // Custom activity indicator UI
    DispatchQueue.main.async {
        activityIndicator.isHidden = !isActive
    }
}

// Requests with automatic activity indication
let users = await JPNetworking.getWithActivity("/users", as: [User].self)
let result = await JPNetworking.postWithActivity("/data", body: .json(data), as: Result.self)

// Manual activity control
let manager = NetworkActivityIndicatorManager.shared
await manager.incrementActivityCount()
// ... perform network operation
await manager.decrementActivityCount()

// SwiftUI integration
struct ContentView: View {
    var body: some View {
        VStack {
            // Your content
        }
        .networkActivityIndicator { isActive in
            if isActive {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
}
```

### 20. Advanced Progress Tracking

```swift
// Download with detailed progress tracking
let response = await NetworkManager.shared.downloadWithProgress(
    "https://example.com/largefile.zip",
    to: destinationURL
) { progress in
    print("Progress: \(progress.fractionCompleted * 100)%")
    print("Speed: \(progress.formattedBytesPerSecond)")
    print("ETA: \(progress.formattedETA)")
    print("Transferred: \(progress.formattedTransferredBytes)")
    print("Total: \(progress.formattedTotalBytes)")
}

// Upload with progress tracking
let uploadResponse = await NetworkManager.shared.uploadWithProgress(
    file: fileURL,
    to: "https://api.example.com/upload"
) { progress in
    updateProgressBar(progress.fractionCompleted)
    updateSpeedLabel(progress.formattedBytesPerSecond)
}

// Manual progress tracking
let progressTracker = ProgressTracker()
progressTracker.start(totalBytes: totalSize)

progressTracker.progressHandler = { progress in
    // Update UI with progress
}

progressTracker.completionHandler = { finalProgress in
    // Handle completion
}

// Update progress during transfer
progressTracker.updateProgress(transferredBytes: currentBytes)
```

### 21. Custom NetworkManager Instances

```swift
// Create custom managers with all advanced features
let cacheConfig = CacheConfiguration(
    memoryCapacity: 100 * 1024 * 1024,
    strategy: .memoryAndDisk,
    defaultTTL: 3600 // 1 hour
)

let retryConfig = RetryConfiguration.aggressive

let sslPolicy = SSLSecurityPolicy.certificatePinning(
    certificates: SSLPinningManager.certificates(in: Bundle.main)
)
let sslManager = SSLPinningManager(policy: sslPolicy)

let customManager = NetworkManager(
    configuration: NetworkConfiguration(
        baseURL: "https://api.custom.com",
        defaultHeaders: ["API-Key": "your-key"],
        timeout: 60.0
    ),
    sslPinningManager: sslManager,
    cacheManager: CacheManager(configuration: cacheConfig),
    retryManager: RetryManager(configuration: retryConfig)
)

let response = await customManager.executeWithActivity(
    JPNetworkingRequest.get("/data"),
    as: CustomData.self,
    cachePolicy: .cacheFirst,
    retryConfiguration: .aggressive
)
```

## 🏗️ Architecture Overview

JPNetworking is built with a modular architecture that separates concerns and promotes maintainability:

### Core Components

1. **NetworkError** - Comprehensive error handling system with 25+ specific error types
2. **JPNetworkingRequest** - Type-safe request building with fluent API and validation
3. **JPNetworkingResponse** - Generic response container with functional programming support
4. **NetworkManager** - Core networking engine with modern Swift concurrency
5. **CacheManager** - Advanced multi-level caching with intelligent eviction policies
6. **RetryManager** - Intelligent retry logic with exponential backoff and jitter
7. **AuthenticationProvider** - Comprehensive auth system (Bearer, Basic, API Key, OAuth 2.0, Custom)
8. **InterceptorManager** - Request/response middleware system with priority-based execution
9. **JPNetworkingLogger** - Advanced logging system with multiple destinations and log levels
10. **NetworkReachabilityManager** - Real-time network monitoring with connection type detection
11. **BackgroundTaskManager** - Background download/upload tasks with progress tracking
12. **SSLPinningManager** - Certificate and public key pinning for enhanced security
13. **ResponseSerializer** - Advanced serialization for JSON, XML, Images, and custom formats
14. **NetworkActivityIndicatorManager** - Automatic activity indicator management
15. **ProgressTracker** - Detailed progress tracking with transfer metrics and ETA
16. **JPNetworking** - Main API facade with convenient static methods and global configuration

### Design Principles

- **Type Safety**: Compile-time guarantees for request/response handling
- **Immutability**: Value semantics for thread safety and predictability
- **Composability**: Functional programming patterns for data transformation
- **Extensibility**: Protocol-based design for easy customization
- **Performance**: Optimized for minimal allocations and maximum throughput

## 🧪 Testing Support

JPNetworking provides comprehensive testing utilities and built-in support:

```swift
// Mock successful response
let mockUser = User(id: 1, name: "Test User", email: "test@example.com")
let successResponse = ResponseBuilder.success(value: mockUser)

// Mock error response
let errorResponse = ResponseBuilder.failure<User>(error: .noInternetConnection)

// Custom NetworkManager for testing
let testManager = NetworkManager(session: mockURLSession)

// Test authentication providers
let testAuth = CustomAuth { request in
    return request.adding(header: "X-Test-Auth", value: "test-token")
}

// Test interceptors
let testInterceptor = LoggingRequestInterceptor(logLevel: .verbose)
await InterceptorManager.shared.addRequestInterceptor(testInterceptor)

// Test caching behavior
let cacheManager = CacheManager(configuration: CacheConfiguration(strategy: .memoryOnly))
let testResponse = await cacheManager.retrieve(for: request, as: TestData.self)
```

## 🔧 Advanced Configuration

### Custom JSON Encoding/Decoding

```swift
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.keyEncodingStrategy = .convertToSnakeCase

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
decoder.keyDecodingStrategy = .convertFromSnakeCase

let response = await JPNetworking.post(
    "/users",
    body: newUser,
    as: User.self,
    encoder: encoder,
    decoder: decoder
)
```

### Custom URLSession Configuration

```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30
config.timeoutIntervalForResource = 60
config.httpMaximumConnectionsPerHost = 4

let session = URLSession(configuration: config)
let manager = NetworkManager(session: session)
```

## 📊 Performance Characteristics

- **Memory Efficient**: Minimal object allocations and smart memory management
- **Concurrent**: Built-in support for concurrent request execution
- **Scalable**: Handles high-throughput scenarios with connection pooling
- **Optimized**: Zero-copy operations where possible
- **Intelligent Caching**: Multi-level caching reduces network requests by up to 80%
- **Smart Retry Logic**: Exponential backoff prevents server overload while ensuring reliability

## 🚀 Advanced Features

### Caching System
- **Multi-Level Storage**: Memory + Disk caching with configurable limits
- **Intelligent Eviction**: LRU, LFU, FIFO, and TTL-based policies
- **Data Compression**: Automatic compression for large responses
- **Cache Statistics**: Monitor hit rates and performance metrics

### Retry Mechanisms  
- **Exponential Backoff**: Intelligent delay calculation with jitter
- **Configurable Policies**: Custom retry conditions and limits
- **Error-Specific Logic**: Different strategies for different error types
- **Performance Monitoring**: Track retry rates and success metrics

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
git clone https://github.com/iamjpsharma/JPNetworking.git
cd JPNetworking
swift build
swift test
```

## 📄 License

JPNetworking is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Inspired by [Alamofire](https://github.com/Alamofire/Alamofire) and [AFNetworking](https://github.com/AFNetworking/AFNetworking)
- Built with modern Swift concurrency patterns
- Designed for the Swift community

## 📞 Support

- 📖 [Documentation](https://iamjpsharma.github.io/JPNetworking)
- 🐛 [Issue Tracker](https://github.com/iamjpsharma/JPNetworking/issues)
- 💬 [Discussions](https://github.com/iamjpsharma/JPNetworking/discussions)
- 📧 Email: sjaiprakash457@gmail.com

---

**Made with ❤️ by Jai Prakash Sharma (@iamjpsharma)**
