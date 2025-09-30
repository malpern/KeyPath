import Foundation

/// A token representing a configuration observation that can be cancelled.
public struct ConfigurationObservationToken {
    private let cancellationHandler: () -> Void

    init(cancellationHandler: @escaping () -> Void) {
        self.cancellationHandler = cancellationHandler
    }

    /// Cancels the configuration observation.
    public func cancel() {
        cancellationHandler()
    }
}

/// Protocol defining configuration management capabilities.
///
/// This protocol establishes a consistent interface for loading, reloading,
/// and observing configuration changes within KeyPath. It provides the foundation
/// for clean separation between configuration management and business logic.
///
/// ## Usage
///
/// Configuration services implement this protocol to provide type-safe
/// configuration management:
///
/// ```swift
/// struct MyConfig {
///     let inputKey: String
///     let outputKey: String
/// }
///
/// class MyConfigService: ConfigurationProviding {
///     typealias Config = MyConfig
///     private var currentConfig = MyConfig(inputKey: "caps", outputKey: "esc")
///
///     func current() async -> MyConfig {
///         return currentConfig
///     }
///
///     func reload() async throws -> MyConfig {
///         // Load from file/network/etc
///         let newConfig = try loadFromDisk()
///         currentConfig = newConfig
///         return newConfig
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods are async and implementations should ensure thread-safe
/// access to configuration state.
@MainActor
protocol ConfigurationProviding: AnyObject {
    /// The type of configuration provided by this service.
    associatedtype Config

    /// Returns the current configuration.
    ///
    /// This method should be fast and return the cached configuration.
    /// For loading fresh configuration, use `reload()`.
    ///
    /// - Returns: The current configuration instance.
    func current() async -> Config

    /// Reloads configuration from its source.
    ///
    /// This method should fetch the latest configuration from its source
    /// (file, network, etc.), validate it, and update the current configuration.
    ///
    /// - Returns: The newly loaded configuration.
    /// - Throws: `ConfigurationError` if loading or validation fails.
    func reload() async throws -> Config

    /// Observes configuration changes.
    ///
    /// The provided callback will be invoked whenever the configuration changes.
    /// The observation continues until the returned token is cancelled.
    ///
    /// - Parameter onChange: Callback invoked when configuration changes.
    /// - Returns: A token that can be used to cancel the observation.
    func observe(_ onChange: @Sendable @escaping (Config) async -> Void) -> ConfigurationObservationToken
}

/// Extension providing convenience methods and default behaviors.
extension ConfigurationProviding {
    /// Reloads configuration and invokes a callback with the result.
    ///
    /// This convenience method handles errors by logging them and provides
    /// a simple callback-based interface for configuration reloading.
    ///
    /// - Parameter completion: Called with the result of the reload operation.
    func reloadWithCallback(_ completion: @Sendable @escaping (Result<Config, Error>) -> Void) {
        Task {
            do {
                let config = try await reload()
                await MainActor.run { completion(.success(config)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Ensures the configuration is fresh by reloading if needed.
    ///
    /// This method can be used to implement cache invalidation or periodic refresh.
    ///
    /// - Parameter maxAge: Maximum age before triggering a reload (in seconds).
    /// - Returns: The current (potentially refreshed) configuration.
    func ensureFresh(maxAge _: TimeInterval = 60) async throws -> Config {
        // Default implementation just returns current - override for cache management
        await current()
    }
}

/// Specialized configuration providing for file-based configurations.
protocol FileConfigurationProviding: ConfigurationProviding {
    /// The file path for the configuration.
    var configurationPath: String { get }

    /// Validates configuration content before applying it.
    ///
    /// - Parameter content: The raw configuration content to validate.
    /// - Returns: The validated configuration instance.
    /// - Throws: `ConfigurationError` if validation fails.
    func validate(content: String) throws -> Config

    /// Monitors the configuration file for changes.
    ///
    /// - Returns: A token that can be used to stop monitoring.
    func startFileMonitoring() -> ConfigurationObservationToken
}

/// Default implementation for file-based configuration providers.
extension FileConfigurationProviding {
    func reload() async throws -> Config {
        guard FileManager.default.fileExists(atPath: configurationPath) else {
            throw KeyPathError.configuration(.fileNotFound(path: configurationPath))
        }

        do {
            let content = try String(contentsOfFile: configurationPath, encoding: .utf8)
            return try validate(content: content)
        } catch let error as KeyPathError {
            throw error
        } catch {
            throw KeyPathError.configuration(.loadFailed(reason: error.localizedDescription))
        }
    }
}

// (Removed deprecated ConfigurationError - now using KeyPathError directly)
