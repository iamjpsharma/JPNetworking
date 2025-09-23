Pod::Spec.new do |s|
  s.name             = 'JPNetworking'
  s.version          = '1.0.0'
  s.summary          = 'Advanced Swift Networking Framework'
  s.description      = <<-DESC
A modern, production-ready networking framework for Swift that rivals AFNetworking and Alamofire. 
Built with modern Swift concurrency, type safety, and developer experience in mind.

Features:
• Modern async/await APIs with Swift concurrency
• Type-safe request building with fluent API
• Comprehensive error handling and recovery
• Advanced caching with intelligent eviction
• Intelligent retry logic with exponential backoff
• Built-in authentication support
• Request/response interceptors
• Advanced logging and monitoring
• Network reachability monitoring
• Background downloads and uploads
• SSL certificate pinning
• Advanced response serialization
• Network activity indicator management
• Detailed progress tracking
                       DESC

  s.homepage         = 'https://github.com/iamjpsharma/JPNetworking'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Jai Prakash Sharma' => 'iamjpsharma@gmail.com' }
  s.source           = { :git => 'https://github.com/iamjpsharma/JPNetworking.git', :tag => s.version.to_s }
  s.social_media_url = 'https://github.com/iamjpsharma'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'

  s.swift_versions = ['5.7', '5.8', '5.9']
  
  s.source_files = 'Sources/JPNetworking/**/*'
  
  s.frameworks = 'Foundation'
  s.ios.frameworks = 'UIKit'
  s.osx.frameworks = 'AppKit'
  
  s.requires_arc = true
  
  # Dependencies
  # s.dependency 'SomeOtherPod', '~> 1.0'
  
  # Test spec
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/JPNetworkingTests/**/*'
  end
end
