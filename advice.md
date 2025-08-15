# KeyPath macOS Application — Architecture and Maintainability Audit (advice.md)

Based on comprehensive analysis of the KeyPath macOS application codebase, this document provides detailed recommendations for improving code organization, architecture quality, and maintainability.

## Executive Summary

KeyPath is a well-structured macOS application for keyboard remapping using Kanata as the backend engine. The codebase demonstrates good separation of concerns with a SwiftUI frontend and LaunchDaemon architecture. However, there are opportunities for improvement in modularity, testing infrastructure, and technical debt reduction.

## 1. Code Organization and Modularity

### Current Strengths
- Clear separation between UI and business logic
- Well-organized InstallationWizard with component-based architecture
- Good use of Swift Package Manager structure
- Logical grouping of related functionality (Managers, Services, UI)

### Areas for Improvement
- **Monolithic app target**: All code exists in a single Swift package, increasing build times and coupling
- **Shared state management**: Some global state leaking across layers (evident in KanataManager singleton pattern)
- **Mixed responsibilities**: Some classes handle multiple concerns (e.g., KanataManager handles both lifecycle and configuration)

### Recommended Target Structure
Split into focused SwiftPM packages:

```
KeyPath/
├── App/ (main app target)
│   ├── App.swift
│   ├── Composition/
│   │   └── DependencyContainer.swift
├── Packages/
│   ├── KeyPathCore/ (domain entities and use cases)
│   ├── KeyPathUI/ (reusable SwiftUI components)
│   ├── KeyPathServices/ (system integration services)
│   ├── KeyPathInstaller/ (installation wizard logic)
│   ├── KeyPathSecurity/ (permissions and security)
│   ├── KeyPathLogging/ (centralized logging)
│   └── KeyPathTestingSupport/ (test utilities)
```

### Actionable Steps
1. **Phase 1**: Extract InstallationWizard into separate package
2. **Phase 2**: Move core business logic to KeyPathCore
3. **Phase 3**: Isolate system services (KanataManager, PermissionService)
4. **Phase 4**: Create shared UI components package

## 2. Architecture Patterns and Consistency

### Current Architecture Assessment
- **Strengths**: Consistent use of SwiftUI with MVVM pattern
- **Inconsistencies**: Mixed use of async/await and Combine
- **Concerns**: Direct system calls scattered throughout codebase

### Recommended Architecture
- **Presentation**: SwiftUI with consistent MVVM pattern
- **Domain**: Clean architecture with use cases and domain services
- **Infrastructure**: Repository pattern for system interactions
- **Cross-cutting**: Dependency injection for testability

### Key Interfaces to Implement
```swift
// Domain Layer
protocol KanataUseCase {
    func startService() async throws
    func stopService() async throws
    func updateConfiguration(_ config: KanataConfig) async throws
}

// Infrastructure Layer
protocol SystemServiceRepository {
    func installLaunchDaemon(_ plist: String) async throws
    func getServiceStatus() async throws -> ServiceStatus
}

// Security Layer
protocol PermissionRepository {
    func requestAccessibility() async throws -> Bool
    func checkInputMonitoring() async throws -> Bool
}
```

## 3. Technical Debt Analysis

### High-Priority Technical Debt

#### 3.1 Singleton Overuse
**Issue**: KanataManager and other services use singleton pattern
**Impact**: Difficult to test, hidden dependencies, potential race conditions
**Solution**: 
```swift
// Replace singleton pattern with dependency injection
final class KanataManager {
    private let systemService: SystemServiceRepository
    private let configManager: ConfigurationRepository
    
    init(systemService: SystemServiceRepository, 
         configManager: ConfigurationRepository) {
        self.systemService = systemService
        self.configManager = configManager
    }
}
```

#### 3.2 Mixed Concurrency Models
**Issue**: Combination of async/await, Combine, and completion handlers
**Impact**: Inconsistent error handling, potential deadlocks
**Solution**: Standardize on async/await with structured concurrency

#### 3.3 System Integration Coupling
**Issue**: Direct system calls throughout the application
**Impact**: Difficult to test, platform-specific code scattered
**Solution**: Abstract system calls behind repository interfaces

### Medium-Priority Technical Debt

#### 3.4 Error Handling Inconsistency
**Current**: Mix of throwing functions, optionals, and error callbacks
**Recommended**: Typed error enums with consistent handling
```swift
enum KanataError: Error {
    case serviceNotFound
    case permissionDenied
    case configurationInvalid(String)
    case systemError(underlying: Error)
}
```

#### 3.5 Configuration Management
**Issue**: Configuration scattered across multiple classes
**Solution**: Centralized configuration service with validation

## 4. Testing Infrastructure Quality

### Current Testing Assessment
- **Strengths**: Comprehensive test suite with integration tests
- **Good practices**: Real system testing approach, test fixtures
- **Areas for improvement**: Some tests require system modifications (sudo access)

### Recommended Testing Strategy

#### 4.1 Test Architecture
```
Tests/
├── UnitTests/ (fast, isolated)
│   ├── DomainTests/
│   ├── UITests/
│   └── UtilityTests/
├── IntegrationTests/ (system interactions)
│   ├── ServiceIntegrationTests/
│   ├── PermissionTests/
│   └── ConfigurationTests/
└── TestSupport/
    ├── MockSystemService.swift
    ├── TestConfigurationFactory.swift
    └── TestPermissionService.swift
```

#### 4.2 Test Infrastructure Improvements
1. **Mock system dependencies**: Create test doubles for system services
2. **Test containers**: Isolated test environments for integration tests
3. **Deterministic tests**: Remove dependency on system state
4. **Fast feedback**: Separate unit tests from integration tests

### Example Test Support
```swift
protocol SystemServiceRepository {
    func installLaunchDaemon(_ plist: String) async throws
}

final class MockSystemService: SystemServiceRepository {
    var shouldFailInstallation = false
    
    func installLaunchDaemon(_ plist: String) async throws {
        if shouldFailInstallation {
            throw SystemError.installationFailed
        }
    }
}
```

## 5. Documentation and Maintainability

### Current Documentation Status
- **Excellent**: CLAUDE.md provides comprehensive guidance
- **Good**: Architecture documentation exists
- **Needs improvement**: Code-level documentation, API documentation

### Recommendations

#### 5.1 Enhanced Documentation
1. **DocC integration**: Add comprehensive API documentation
2. **Architecture Decision Records**: Document key decisions
3. **Contribution guidelines**: Standardize development practices
4. **Code comments**: Focus on "why" not "what"

#### 5.2 Code Quality Tools
```bash
# Add to development workflow
swiftformat Sources/ Tests/ --swiftversion 5.9
swiftlint --fix --quiet
swift test --enable-code-coverage
```

#### 5.3 Developer Experience
- Pre-commit hooks for formatting and linting
- Automated documentation generation
- Clear onboarding documentation

## 6. Performance Considerations

### Current Performance Profile
- **Strengths**: Efficient SwiftUI implementation, good system service management
- **Concerns**: Potential main thread blocking in system operations

### Optimization Recommendations

#### 6.1 Concurrency Optimization
```swift
// Use actors for shared state
actor KanataConfigurationStore {
    private var currentConfig: KanataConfig?
    
    func updateConfig(_ config: KanataConfig) async {
        currentConfig = config
        // Notify observers
    }
}
```

#### 6.2 Resource Management
- Background processing for system operations
- Lazy loading of heavy resources
- Proper memory management for observers

#### 6.3 System Integration Performance
- Batch system operations where possible
- Cache system state checks
- Use efficient file watching for configuration changes

## 7. Security Practices

### Current Security Posture
- **Strengths**: Proper permission handling, secure system integration
- **Good practices**: Input validation, error handling

### Security Recommendations

#### 7.1 Enhanced Security Architecture
```swift
protocol SecureConfigurationStore {
    func store(_ config: KanataConfig) async throws
    func retrieve() async throws -> KanataConfig?
    func validateIntegrity() async throws -> Bool
}
```

#### 7.2 Security Best Practices
1. **Input validation**: Sanitize all configuration inputs
2. **Secure storage**: Use Keychain for sensitive data
3. **Privilege separation**: Minimize elevated permissions
4. **Audit logging**: Log security-relevant events

#### 7.3 System Security
- App sandboxing where possible
- Minimal required entitlements
- Secure communication with system services

## 8. Implementation Roadmap

### Phase 1: Foundation (1-2 weeks)
1. **Dependency injection setup**: Create DependencyContainer
2. **Error handling standardization**: Implement typed errors
3. **Logging centralization**: Unified logging strategy

### Phase 2: Modularization (2-3 weeks)
1. **Extract core domain**: Create KeyPathCore package
2. **Service abstraction**: Implement repository patterns
3. **UI componentization**: Extract reusable UI components

### Phase 3: Testing Enhancement (1-2 weeks)
1. **Test infrastructure**: Create mock implementations
2. **Unit test expansion**: Cover core business logic
3. **Integration test optimization**: Reduce system dependencies

### Phase 4: Security & Performance (1-2 weeks)
1. **Security hardening**: Implement secure storage
2. **Performance optimization**: Add concurrency improvements
3. **Documentation completion**: Full API documentation

## 9. Specific File Recommendations

### High-Impact Refactoring Targets

#### 9.1 KanataManager.swift
- **Current**: Monolithic service manager
- **Target**: Split into KanataLifecycleService and KanataConfigurationService
- **Benefit**: Better testability, clearer responsibilities

#### 9.2 InstallationWizard/
- **Current**: Well-structured but could be more modular
- **Target**: Extract into separate package with clear API
- **Benefit**: Reusable across different installation contexts

#### 9.3 SystemStateDetector.swift
- **Current**: Good separation of concerns
- **Target**: Add comprehensive error handling and logging
- **Benefit**: Better debugging and error recovery

### New Files to Create
1. **DependencyContainer.swift**: Central dependency management
2. **KanataErrors.swift**: Centralized error definitions
3. **SystemServiceRepository.swift**: Abstract system interactions
4. **ConfigurationValidator.swift**: Input validation logic
5. **SecurityManager.swift**: Permission and security handling

## 10. Migration Strategy

### Risk Mitigation
- **Incremental changes**: Implement changes in small, reviewable increments
- **Feature flags**: Use configuration to enable/disable new architecture
- **Comprehensive testing**: Maintain test coverage during refactoring
- **Rollback plan**: Ensure each phase can be safely reverted

### Success Metrics
- **Build time improvement**: Target 20% reduction through modularization
- **Test execution speed**: Faster unit tests through better isolation
- **Code coverage**: Maintain >80% coverage during refactoring
- **Developer productivity**: Reduced onboarding time for new features

## Conclusion

KeyPath demonstrates solid foundational architecture with room for improvement in modularity, testing, and maintainability. The recommended changes will enhance code quality, developer productivity, and system reliability while maintaining the application's current strengths.

The modular approach will enable better testing, clearer ownership of code, and easier feature development. The security and performance improvements will ensure the application remains robust and efficient as it grows.

Priority should be given to dependency injection and error handling standardization, as these foundational changes will enable all subsequent improvements.