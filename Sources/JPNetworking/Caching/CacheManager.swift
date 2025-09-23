//
//  CacheManager.swift
//  JPNetworking
//
//  Advanced caching system with multiple strategies and automatic cache management.
//  Provides memory and disk caching with TTL, size limits, and intelligent eviction.
//

import Foundation

// MARK: - Cache Configuration

/// Configuration for cache behavior and limits
///
/// Defines caching strategies, size limits, TTL policies, and storage options.
/// Supports both memory and disk caching with intelligent eviction policies.
///
/// **Usage:**
/// ```swift
/// let config = CacheConfiguration(
///     memoryCapacity: 50 * 1024 * 1024, // 50MB
///     diskCapacity: 200 * 1024 * 1024,  // 200MB
///     defaultTTL: 300, // 5 minutes
///     strategy: .memoryAndDisk
/// )
/// ```
public struct CacheConfiguration: Sendable {
    
    /// Cache storage strategies
    public enum Strategy: Sendable {
        /// Memory-only caching (fastest, limited capacity)
        case memoryOnly
        /// Disk-only caching (persistent, slower access)
        case diskOnly
        /// Memory + Disk caching (best performance + persistence)
        case memoryAndDisk
        /// No caching
        case none
    }
    
    /// Cache eviction policies
    public enum EvictionPolicy: Sendable {
        /// Least Recently Used - evict oldest accessed items
        case lru
        /// Least Frequently Used - evict least accessed items
        case lfu
        /// First In First Out - evict oldest items
        case fifo
        /// Time-based - evict expired items first
        case ttl
    }
    
    // MARK: - Properties
    
    /// Maximum memory cache size in bytes
    public let memoryCapacity: Int
    
    /// Maximum disk cache size in bytes
    public let diskCapacity: Int
    
    /// Default time-to-live for cached items (seconds)
    public let defaultTTL: TimeInterval
    
    /// Cache storage strategy
    public let strategy: Strategy
    
    /// Cache eviction policy
    public let evictionPolicy: EvictionPolicy
    
    /// Whether to cache responses with errors
    public let cacheErrors: Bool
    
    /// Custom cache directory (nil for default)
    public let customCacheDirectory: URL?
    
    /// Whether to compress cached data
    public let compressionEnabled: Bool
    
    /// Minimum response size to compress (bytes)
    public let compressionThreshold: Int
    
    // MARK: - Initializer
    
    public init(
        memoryCapacity: Int = 20 * 1024 * 1024, // 20MB default
        diskCapacity: Int = 100 * 1024 * 1024,  // 100MB default
        defaultTTL: TimeInterval = 300,          // 5 minutes default
        strategy: Strategy = .memoryAndDisk,
        evictionPolicy: EvictionPolicy = .lru,
        cacheErrors: Bool = false,
        customCacheDirectory: URL? = nil,
        compressionEnabled: Bool = true,
        compressionThreshold: Int = 1024 // 1KB
    ) {
        self.memoryCapacity = memoryCapacity
        self.diskCapacity = diskCapacity
        self.defaultTTL = defaultTTL
        self.strategy = strategy
        self.evictionPolicy = evictionPolicy
        self.cacheErrors = cacheErrors
        self.customCacheDirectory = customCacheDirectory
        self.compressionEnabled = compressionEnabled
        self.compressionThreshold = compressionThreshold
    }
}

// MARK: - Cache Entry

/// Individual cache entry with metadata
internal struct CacheEntry: Codable, Sendable {
    let data: Data
    let response: CachedHTTPResponse
    let timestamp: Date
    let expirationDate: Date
    let accessCount: Int
    let lastAccessDate: Date
    let isCompressed: Bool
    
    var isExpired: Bool {
        return Date() > expirationDate
    }
    
    var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }
}

/// Codable wrapper for HTTPURLResponse
internal struct CachedHTTPResponse: Codable, Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let version: String?
    
    init(from response: HTTPURLResponse) {
        self.url = response.url ?? URL(string: "about:blank")!
        self.statusCode = response.statusCode
        
        var convertedHeaders: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                convertedHeaders[keyString] = valueString
            }
        }
        self.headers = convertedHeaders
        self.version = "HTTP/1.1"
    }
    
    func toHTTPURLResponse() -> HTTPURLResponse? {
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: version,
            headerFields: headers
        )
    }
}

// MARK: - Cache Manager

/// Advanced cache manager with memory and disk storage
///
/// Provides intelligent caching with multiple strategies, automatic eviction,
/// and performance optimization. Thread-safe with actor-based isolation.
///
/// **Features:**
/// - Memory and disk caching with configurable limits
/// - TTL-based expiration with automatic cleanup
/// - Multiple eviction policies (LRU, LFU, FIFO, TTL)
/// - Data compression for large responses
/// - Thread-safe operations with Swift actors
/// - Cache statistics and monitoring
///
/// **Usage:**
/// ```swift
/// let cacheManager = CacheManager(configuration: cacheConfig)
/// 
/// // Cache a response
/// await cacheManager.store(response, for: request, ttl: 600)
/// 
/// // Retrieve cached response
/// if let cachedResponse = await cacheManager.retrieve(for: request) {
///     // Use cached response
/// }
/// ```
@globalActor
public actor CacheManager {
    
    public static let shared = CacheManager()
    
    // MARK: - Properties
    
    private let configuration: CacheConfiguration
    private var memoryCache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = [] // For LRU
    private var accessCount: [String: Int] = [:] // For LFU
    
    private let diskCacheURL: URL
    private let fileManager = FileManager.default
    
    // Cache statistics
    private var stats = CacheStatistics()
    
    // MARK: - Initialization
    
    public init(configuration: CacheConfiguration = CacheConfiguration()) {
        self.configuration = configuration
        
        // Setup disk cache directory
        if let customDir = configuration.customCacheDirectory {
            self.diskCacheURL = customDir
        } else {
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.diskCacheURL = cacheDir.appendingPathComponent("JPNetworking")
        }
        
        // Create cache directory if needed
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Start cleanup timer
        Task {
            await startPeriodicCleanup()
        }
    }
    
    // MARK: - Public API
    
    /// Store response in cache
    /// - Parameters:
    ///   - response: JPNetworking response to cache
    ///   - request: Original request (used as cache key)
    ///   - ttl: Time-to-live override (nil for default)
    public func store<T>(
        _ response: JPNetworkingResponse<T>,
        for request: JPNetworkingRequest,
        ttl: TimeInterval? = nil
    ) async {
        guard configuration.strategy != .none else { return }
        guard let data = response.data, let httpResponse = response.response else { return }
        
        // Don't cache errors unless configured to do so
        if !configuration.cacheErrors && response.error != nil {
            return
        }
        
        let cacheKey = generateCacheKey(for: request)
        let effectiveTTL = ttl ?? configuration.defaultTTL
        let expirationDate = Date().addingTimeInterval(effectiveTTL)
        
        // Compress data if enabled and above threshold
        let finalData: Data
        let isCompressed: Bool
        
        if configuration.compressionEnabled && data.count > configuration.compressionThreshold {
            if let compressedData = try? data.compressed() {
                finalData = compressedData
                isCompressed = compressedData.count < data.count
            } else {
                finalData = data
                isCompressed = false
            }
        } else {
            finalData = data
            isCompressed = false
        }
        
        let entry = CacheEntry(
            data: finalData,
            response: CachedHTTPResponse(from: httpResponse),
            timestamp: Date(),
            expirationDate: expirationDate,
            accessCount: 0,
            lastAccessDate: Date(),
            isCompressed: isCompressed
        )
        
        // Store in memory cache
        if configuration.strategy == .memoryOnly || configuration.strategy == .memoryAndDisk {
            await storeInMemory(entry, key: cacheKey)
        }
        
        // Store in disk cache
        if configuration.strategy == .diskOnly || configuration.strategy == .memoryAndDisk {
            await storeToDisk(entry, key: cacheKey)
        }
        
        stats.storeCount += 1
    }
    
    /// Retrieve cached response
    /// - Parameter request: Original request (used as cache key)
    /// - Returns: Cached response or nil if not found/expired
    public func retrieve<T: Decodable & Sendable>(
        for request: JPNetworkingRequest,
        as type: T.Type
    ) async -> JPNetworkingResponse<T>? {
        guard configuration.strategy != .none else { return nil }
        
        let cacheKey = generateCacheKey(for: request)
        
        // Try memory cache first
        if let entry = await retrieveFromMemory(key: cacheKey) {
            stats.hitCount += 1
            return await convertToResponse(entry, type: type, request: request)
        }
        
        // Try disk cache
        if let entry = await retrieveFromDisk(key: cacheKey) {
            stats.hitCount += 1
            
            // Promote to memory cache if using memory+disk strategy
            if configuration.strategy == .memoryAndDisk {
                await storeInMemory(entry, key: cacheKey)
            }
            
            return await convertToResponse(entry, type: type, request: request)
        }
        
        stats.missCount += 1
        return nil
    }
    
    /// Clear all cached data
    public func clearAll() async {
        memoryCache.removeAll()
        accessOrder.removeAll()
        accessCount.removeAll()
        
        // Clear disk cache
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        stats = CacheStatistics()
    }
    
    /// Clear expired entries
    public func clearExpired() async {
        let now = Date()
        
        // Clear expired memory entries
        let expiredKeys = memoryCache.compactMap { key, entry in
            entry.expirationDate < now ? key : nil
        }
        
        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            accessCount.removeValue(forKey: key)
        }
        
        // Clear expired disk entries
        await clearExpiredDiskEntries()
    }
    
    /// Get cache statistics
    public func getStatistics() -> CacheStatistics {
        return stats
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(for request: JPNetworkingRequest) -> String {
        let url = request.url
        let method = request.method.rawValue
        let headers = request.headers.sorted { $0.key < $1.key }
        
        var keyComponents = [method, url]
        
        // Include relevant headers in cache key
        for (key, value) in headers {
            if key.lowercased() != "authorization" { // Don't include auth in cache key
                keyComponents.append("\(key):\(value)")
            }
        }
        
        let keyString = keyComponents.joined(separator: "|")
        return keyString.sha256
    }
    
    private func storeInMemory(_ entry: CacheEntry, key: String) async {
        // Check memory capacity and evict if necessary
        await enforceMemoryCapacity()
        
        memoryCache[key] = entry
        updateAccessTracking(key: key)
    }
    
    private func storeToDisk(_ entry: CacheEntry, key: String) async {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL)
        } catch {
            // Handle encoding/writing errors silently
        }
    }
    
    private func retrieveFromMemory(key: String) async -> CacheEntry? {
        guard let entry = memoryCache[key] else { return nil }
        
        if entry.isExpired {
            memoryCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            accessCount.removeValue(forKey: key)
            return nil
        }
        
        updateAccessTracking(key: key)
        return entry
    }
    
    private func retrieveFromDisk(key: String) async -> CacheEntry? {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let entry = try JSONDecoder().decode(CacheEntry.self, from: data)
            
            if entry.isExpired {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            
            return entry
        } catch {
            // Remove corrupted cache file
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }
    
    private func convertToResponse<T: Decodable & Sendable>(
        _ entry: CacheEntry,
        type: T.Type,
        request: JPNetworkingRequest
    ) async -> JPNetworkingResponse<T>? {
        // Decompress data if needed
        let finalData: Data
        if entry.isCompressed {
            if let decompressedData = try? entry.data.decompressed() {
                finalData = decompressedData
            } else {
                finalData = entry.data
            }
        } else {
            finalData = entry.data
        }
        
        // Convert cached response back to HTTPURLResponse
        guard let httpResponse = entry.response.toHTTPURLResponse() else {
            return nil
        }
        
        // Create data response first
        let dataResponse = JPNetworkingResponse<Data>(
            data: finalData,
            response: httpResponse,
            request: request,
            value: finalData,
            error: nil
        )
        
        // Decode to target type
        return dataResponse.decoded(to: type)
    }
    
    private func updateAccessTracking(key: String) {
        // Update LRU order
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        
        // Update LFU count
        accessCount[key, default: 0] += 1
    }
    
    private func enforceMemoryCapacity() async {
        let currentSize = memoryCache.values.reduce(0) { $0 + $1.data.count }
        
        guard currentSize > configuration.memoryCapacity else { return }
        
        // Evict entries based on policy
        switch configuration.evictionPolicy {
        case .lru:
            await evictLRU()
        case .lfu:
            await evictLFU()
        case .fifo:
            await evictFIFO()
        case .ttl:
            await evictExpired()
        }
    }
    
    private func evictLRU() async {
        while !accessOrder.isEmpty {
            let oldestKey = accessOrder.removeFirst()
            memoryCache.removeValue(forKey: oldestKey)
            accessCount.removeValue(forKey: oldestKey)
            
            let currentSize = memoryCache.values.reduce(0) { $0 + $1.data.count }
            if currentSize <= configuration.memoryCapacity {
                break
            }
        }
    }
    
    private func evictLFU() async {
        let sortedByFrequency = accessCount.sorted { $0.value < $1.value }
        
        for (key, _) in sortedByFrequency {
            memoryCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            accessCount.removeValue(forKey: key)
            
            let currentSize = memoryCache.values.reduce(0) { $0 + $1.data.count }
            if currentSize <= configuration.memoryCapacity {
                break
            }
        }
    }
    
    private func evictFIFO() async {
        let sortedByTimestamp = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
        
        for (key, _) in sortedByTimestamp {
            memoryCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            accessCount.removeValue(forKey: key)
            
            let currentSize = memoryCache.values.reduce(0) { $0 + $1.data.count }
            if currentSize <= configuration.memoryCapacity {
                break
            }
        }
    }
    
    private func evictExpired() async {
        await clearExpired()
        
        // If still over capacity after clearing expired, fall back to LRU
        let currentSize = memoryCache.values.reduce(0) { $0 + $1.data.count }
        if currentSize > configuration.memoryCapacity {
            await evictLRU()
        }
    }
    
    private func clearExpiredDiskEntries() async {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let entry = try JSONDecoder().decode(CacheEntry.self, from: data)
                    
                    if entry.isExpired {
                        try fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    // Remove corrupted files
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Handle directory read errors silently
        }
    }
    
    private func startPeriodicCleanup() async {
        while true {
            try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
            await clearExpired()
        }
    }
}

// MARK: - Cache Statistics

/// Cache performance statistics
public struct CacheStatistics: Sendable {
    public var hitCount: Int = 0
    public var missCount: Int = 0
    public var storeCount: Int = 0
    
    public var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }
    
    public var totalRequests: Int {
        return hitCount + missCount
    }
}

// MARK: - Data Compression Extensions

private extension Data {
    func compressed() throws -> Data {
        return try (self as NSData).compressed(using: .lzfse) as Data
    }
    
    func decompressed() throws -> Data {
        return try (self as NSData).decompressed(using: .lzfse) as Data
    }
}

// MARK: - String Hashing Extension

private extension String {
    var sha256: String {
        let data = self.data(using: .utf8) ?? Data()
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// Import CommonCrypto for hashing
import CommonCrypto

/*
 🗄️ CACHE MANAGER ARCHITECTURE EXPLANATION:
 
 1. MULTI-LEVEL CACHING:
    - Memory cache for fastest access (configurable size limit)
    - Disk cache for persistence across app launches
    - Intelligent promotion from disk to memory
 
 2. ADVANCED EVICTION POLICIES:
    - LRU (Least Recently Used) - default, good for most cases
    - LFU (Least Frequently Used) - good for stable access patterns
    - FIFO (First In First Out) - simple, predictable
    - TTL (Time To Live) - expire old entries first
 
 3. PERFORMANCE OPTIMIZATIONS:
    - Data compression for large responses (configurable threshold)
    - Async/await with actor isolation for thread safety
    - Periodic cleanup to remove expired entries
    - Smart cache key generation including relevant headers
 
 4. PRODUCTION FEATURES:
    - Comprehensive cache statistics and monitoring
    - Configurable TTL per request or global default
    - Error response caching (optional)
    - Custom cache directory support
    - Automatic capacity management
 
 5. THREAD SAFETY:
    - Actor-based isolation ensures thread safety
    - No locks or semaphores needed
    - Concurrent access handled by Swift runtime
 */
