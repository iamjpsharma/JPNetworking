//
//  NetworkActivityIndicatorManager.swift
//  JPNetworking
//
//  Network activity indicator management for iOS and macOS applications.
//  Provides automatic network activity indication with request counting and timing.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Network Activity Indicator Manager

/// Network activity indicator manager
///
/// Manages the network activity indicator in the status bar (iOS) or provides
/// activity state for custom indicators (macOS). Automatically tracks active
/// network requests and shows/hides the indicator accordingly.
///
/// **Features:**
/// - Automatic request counting and indicator management
/// - Configurable delay before showing/hiding indicator
/// - Thread-safe request tracking
/// - Custom activity state callbacks
/// - Integration with JPNetworking requests
///
/// **Usage:**
/// ```swift
/// // Enable automatic management
/// NetworkActivityIndicatorManager.shared.isEnabled = true
/// 
/// // Manual control
/// NetworkActivityIndicatorManager.shared.incrementActivityCount()
/// NetworkActivityIndicatorManager.shared.decrementActivityCount()
/// 
/// // Custom activity callback
/// NetworkActivityIndicatorManager.shared.activityStateChangeHandler = { isActive in
///     // Update custom UI indicator
/// }
/// ```
@MainActor
public final class NetworkActivityIndicatorManager: ObservableObject {
    
    public static let shared = NetworkActivityIndicatorManager()
    
    // MARK: - Properties
    
    /// Whether the manager is enabled
    @Published public var isEnabled: Bool = false {
        didSet {
            if !isEnabled {
                resetActivityCount()
            }
        }
    }
    
    /// Whether network activity is currently active
    @Published public var isNetworkActivityIndicatorVisible: Bool = false
    
    /// Current number of active network requests
    @Published public var activeRequestCount: Int = 0
    
    /// Delay before showing the activity indicator (seconds)
    public var activationDelay: TimeInterval = 0.1
    
    /// Delay before hiding the activity indicator (seconds)
    public var deactivationDelay: TimeInterval = 0.1
    
    /// Custom activity state change handler
    public var activityStateChangeHandler: (@MainActor (Bool) -> Void)?
    
    // Private properties
    private var activationTimer: Timer?
    private var deactivationTimer: Timer?
    private let activityQueue = DispatchQueue(label: "JPNetworking.ActivityIndicator", attributes: .concurrent)
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Increment the activity count
    public func incrementActivityCount() {
        guard isEnabled else { return }
        
        activityQueue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.activeRequestCount += 1
                self.updateActivityIndicatorState()
            }
        }
    }
    
    /// Decrement the activity count
    public func decrementActivityCount() {
        guard isEnabled else { return }
        
        activityQueue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.activeRequestCount = max(0, self.activeRequestCount - 1)
                self.updateActivityIndicatorState()
            }
        }
    }
    
    /// Reset the activity count to zero
    public func resetActivityCount() {
        activityQueue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.activeRequestCount = 0
                self.updateActivityIndicatorState()
            }
        }
    }
    
    /// Manually set the network activity indicator visibility
    /// - Parameter visible: Whether the indicator should be visible
    public func setNetworkActivityIndicatorVisible(_ visible: Bool) {
        guard isEnabled else { return }
        
        isNetworkActivityIndicatorVisible = visible
        updatePlatformIndicator()
        activityStateChangeHandler?(visible)
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func applicationDidEnterBackground() {
        // Hide indicator when app goes to background
        setNetworkActivityIndicatorVisible(false)
    }
    
    @objc private func applicationWillEnterForeground() {
        // Restore indicator state when app comes to foreground
        updateActivityIndicatorState()
    }
    
    private func updateActivityIndicatorState() {
        let shouldShow = activeRequestCount > 0
        
        if shouldShow && !isNetworkActivityIndicatorVisible {
            showActivityIndicatorWithDelay()
        } else if !shouldShow && isNetworkActivityIndicatorVisible {
            hideActivityIndicatorWithDelay()
        }
    }
    
    private func showActivityIndicatorWithDelay() {
        // Cancel any pending deactivation
        deactivationTimer?.invalidate()
        deactivationTimer = nil
        
        // Don't show if already visible
        guard !isNetworkActivityIndicatorVisible else { return }
        
        if activationDelay > 0 {
            activationTimer?.invalidate()
            activationTimer = Timer.scheduledTimer(withTimeInterval: activationDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.setNetworkActivityIndicatorVisible(true)
                }
            }
        } else {
            setNetworkActivityIndicatorVisible(true)
        }
    }
    
    private func hideActivityIndicatorWithDelay() {
        // Cancel any pending activation
        activationTimer?.invalidate()
        activationTimer = nil
        
        // Don't hide if already hidden
        guard isNetworkActivityIndicatorVisible else { return }
        
        if deactivationDelay > 0 {
            deactivationTimer?.invalidate()
            deactivationTimer = Timer.scheduledTimer(withTimeInterval: deactivationDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.setNetworkActivityIndicatorVisible(false)
                }
            }
        } else {
            setNetworkActivityIndicatorVisible(false)
        }
    }
    
    private func updatePlatformIndicator() {
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        // iOS status bar network activity indicator
        if #available(iOS 13.0, *) {
            // Network activity indicator was deprecated in iOS 13
            // Modern apps should use custom indicators
        } else {
            UIApplication.shared.isNetworkActivityIndicatorVisible = isNetworkActivityIndicatorVisible
        }
        #endif
        
        // For macOS and modern iOS, rely on the custom handler
    }
}

// MARK: - Network Activity Tracking

/// Network activity tracking for automatic indicator management
public final class NetworkActivityTracker: Sendable {
    
    private let manager: NetworkActivityIndicatorManager
    private let identifier: UUID
    
    public init(manager: NetworkActivityIndicatorManager = .shared) {
        self.manager = manager
        self.identifier = UUID()
    }
    
    /// Start tracking network activity
    public func startActivity() {
        Task { @MainActor in
            manager.incrementActivityCount()
        }
    }
    
    /// Stop tracking network activity
    public func stopActivity() {
        Task { @MainActor in
            manager.decrementActivityCount()
        }
    }
}

// MARK: - NetworkManager Integration

extension NetworkManager {
    
    /// Execute request with automatic activity indicator management
    /// - Parameters:
    ///   - request: Request to execute
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder
    ///   - cachePolicy: Cache policy
    ///   - retryConfiguration: Retry configuration
    ///   - showActivityIndicator: Whether to show activity indicator
    /// - Returns: Response with activity tracking
    public func executeWithActivity<T: Decodable & Sendable>(
        _ request: JPNetworkingRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        cachePolicy: CachePolicy = .default,
        retryConfiguration: RetryConfiguration? = nil,
        showActivityIndicator: Bool = true
    ) async -> JPNetworkingResponse<T> {
        
        let tracker = showActivityIndicator ? NetworkActivityTracker() : nil
        tracker?.startActivity()
        
        defer {
            tracker?.stopActivity()
        }
        
        return await execute(
            request,
            as: type,
            decoder: decoder,
            cachePolicy: cachePolicy,
            retryConfiguration: retryConfiguration
        )
    }
    
    /// GET request with activity indicator
    /// - Parameters:
    ///   - url: Request URL
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder
    ///   - showActivityIndicator: Whether to show activity indicator
    /// - Returns: Response with activity tracking
    public func getWithActivity<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        showActivityIndicator: Bool = true
    ) async -> JPNetworkingResponse<T> {
        
        let request = JPNetworkingRequest.get(url)
        return await executeWithActivity(
            request,
            as: type,
            decoder: decoder,
            showActivityIndicator: showActivityIndicator
        )
    }
    
    /// POST request with activity indicator
    /// - Parameters:
    ///   - url: Request URL
    ///   - body: Request body
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder
    ///   - showActivityIndicator: Whether to show activity indicator
    /// - Returns: Response with activity tracking
    public func postWithActivity<T: Decodable & Sendable>(
        _ url: String,
        body: RequestBody = .none,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        showActivityIndicator: Bool = true
    ) async -> JPNetworkingResponse<T> {
        
        let request = JPNetworkingRequest.post(url, body: body)
        return await executeWithActivity(
            request,
            as: type,
            decoder: decoder,
            showActivityIndicator: showActivityIndicator
        )
    }
}

// MARK: - JPNetworking Integration

extension JPNetworking {
    
    /// Configure network activity indicator
    /// - Parameters:
    ///   - enabled: Whether activity indicator is enabled
    ///   - activationDelay: Delay before showing indicator
    ///   - deactivationDelay: Delay before hiding indicator
    ///   - customHandler: Custom activity state handler
    @MainActor
    public static func configureActivityIndicator(
        enabled: Bool = true,
        activationDelay: TimeInterval = 0.1,
        deactivationDelay: TimeInterval = 0.1,
        customHandler: (@MainActor (Bool) -> Void)? = nil
    ) {
        let manager = NetworkActivityIndicatorManager.shared
        manager.isEnabled = enabled
        manager.activationDelay = activationDelay
        manager.deactivationDelay = deactivationDelay
        manager.activityStateChangeHandler = customHandler
    }
    
    /// GET request with automatic activity indicator
    /// - Parameters:
    ///   - url: Request URL
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder
    /// - Returns: Response with activity tracking
    @MainActor
    public static func getWithActivity<T: Decodable & Sendable>(
        _ url: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.getWithActivity(url, as: type, decoder: decoder)
    }
    
    /// POST request with automatic activity indicator
    /// - Parameters:
    ///   - url: Request URL
    ///   - body: Request body
    ///   - type: Target Decodable type
    ///   - decoder: JSON decoder
    /// - Returns: Response with activity tracking
    @MainActor
    public static func postWithActivity<T: Decodable & Sendable>(
        _ url: String,
        body: RequestBody = .none,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> JPNetworkingResponse<T> {
        return await manager.postWithActivity(url, body: body, as: type, decoder: decoder)
    }
}

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension NetworkActivityIndicatorManager {
    
    /// SwiftUI view modifier for custom activity indicators
    public func activityIndicator<Content: View>(
        @ViewBuilder content: @escaping (Bool) -> Content
    ) -> some View {
        content(isNetworkActivityIndicatorVisible)
    }
}

/// SwiftUI view modifier for network activity indication
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct NetworkActivityIndicator: ViewModifier {
    @ObservedObject private var manager = NetworkActivityIndicatorManager.shared
    private let content: (Bool) -> AnyView
    
    public init<Content: View>(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = { isActive in AnyView(content(isActive)) }
    }
    
    public func body(content: Content) -> some View {
        ZStack {
            content
            self.content(manager.isNetworkActivityIndicatorVisible)
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View {
    /// Add a network activity indicator to this view
    /// - Parameter content: Content to show when network is active
    /// - Returns: View with activity indicator
    public func networkActivityIndicator<Content: View>(
        @ViewBuilder content: @escaping (Bool) -> Content
    ) -> some View {
        modifier(NetworkActivityIndicator(content: content))
    }
}

#endif

/*
 📶 NETWORK ACTIVITY INDICATOR ARCHITECTURE EXPLANATION:
 
 1. AUTOMATIC MANAGEMENT:
    - Request counting with thread-safe operations
    - Configurable activation/deactivation delays
    - Platform-specific indicator integration
    - Background/foreground state handling
 
 2. CROSS-PLATFORM SUPPORT:
    - iOS: Status bar indicator (legacy) + custom handlers
    - macOS: Custom indicator support via callbacks
    - tvOS/watchOS: Custom indicator support
    - SwiftUI: Built-in view modifiers and integration
 
 3. FLEXIBLE INTEGRATION:
    - Automatic tracking with NetworkManager methods
    - Manual control for custom scenarios
    - JPNetworking static method integration
    - Observable object for SwiftUI binding
 
 4. PRODUCTION FEATURES:
    - Thread-safe request counting
    - Memory efficient tracking
    - Proper cleanup and resource management
    - Background/foreground state preservation
 
 5. DEVELOPER EXPERIENCE:
    - Simple enable/disable configuration
    - Custom activity state callbacks
    - SwiftUI view modifiers for custom indicators
    - Automatic integration with existing APIs
 
 6. PERFORMANCE:
    - Minimal overhead tracking
    - Efficient timer management
    - Optimized state updates
    - Memory leak prevention
 */
