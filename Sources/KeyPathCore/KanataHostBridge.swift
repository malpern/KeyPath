import Darwin
import Foundation

public enum KanataHostBridgeProbeResult: Equatable, Sendable {
    case loaded(version: String, defaultConfigCount: Int)
    case unavailable(reason: String)

    public var logSummary: String {
        switch self {
        case let .loaded(version, defaultConfigCount):
            "Host bridge loaded: version=\(version) default_cfg_count=\(defaultConfigCount)"
        case let .unavailable(reason):
            "Host bridge unavailable: \(reason)"
        }
    }
}

public enum KanataHostBridgeValidationResult: Equatable, Sendable {
    case valid
    case invalid(reason: String)
    case unavailable(reason: String)

    public var logSummary: String {
        switch self {
        case .valid:
            "Host bridge validated config successfully"
        case let .invalid(reason):
            "Host bridge config validation failed: \(reason)"
        case let .unavailable(reason):
            "Host bridge config validation unavailable: \(reason)"
        }
    }
}

public enum KanataHostBridgeRuntimeResult: Equatable, Sendable {
    case created(layerCount: Int)
    case unavailable(reason: String)
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case let .created(layerCount):
            "Host bridge created runtime successfully: layer_count=\(layerCount)"
        case let .unavailable(reason):
            "Host bridge runtime creation unavailable: \(reason)"
        case let .failed(reason):
            "Host bridge runtime creation failed: \(reason)"
        }
    }
}

public enum KanataHostBridgeRunResult: Equatable, Sendable {
    case completed
    case unavailable(reason: String)
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case .completed:
            "Host bridge runtime exited cleanly"
        case let .unavailable(reason):
            "Host bridge runtime unavailable: \(reason)"
        case let .failed(reason):
            "Host bridge runtime failed: \(reason)"
        }
    }
}

public enum KanataHostBridgePassthruRuntimeResult: Equatable, Sendable {
    case created(layerCount: Int)
    case unavailable(reason: String)
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case let .created(layerCount):
            "Host bridge passthru runtime created successfully: layer_count=\(layerCount)"
        case let .unavailable(reason):
            "Host bridge passthru runtime unavailable: \(reason)"
        case let .failed(reason):
            "Host bridge passthru runtime failed: \(reason)"
        }
    }
}

public struct KanataHostBridgePassthruOutputEvent: Equatable, Sendable {
    public let value: UInt64
    public let usagePage: UInt32
    public let usage: UInt32

    public init(value: UInt64, usagePage: UInt32, usage: UInt32) {
        self.value = value
        self.usagePage = usagePage
        self.usage = usage
    }
}

public enum KanataHostBridgePassthruReceiveError: Error, Equatable, Sendable {
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case let .failed(reason):
            "Host bridge passthru receive failed: \(reason)"
        }
    }
}

public enum KanataHostBridgePassthruStartError: Error, Equatable, Sendable {
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case let .failed(reason):
            "Host bridge passthru start failed: \(reason)"
        }
    }
}

public enum KanataHostBridgePassthruSendInputError: Error, Equatable, Sendable {
    case failed(reason: String)

    public var logSummary: String {
        switch self {
        case let .failed(reason):
            "Host bridge passthru send-input failed: \(reason)"
        }
    }
}

public final class KanataHostBridgePassthruRuntimeHandle: @unchecked Sendable {
    fileprivate typealias DestroyPassthruRuntimeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    fileprivate typealias StartPassthruRuntimeFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    fileprivate typealias TryReceivePassthruOutputFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt64>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Int32
    fileprivate typealias SendPassthruInputFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UInt32,
        UInt32,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool

    private let bridgeHandle: UnsafeMutableRawPointer
    private let runtimeHandle: UnsafeMutableRawPointer
    private let destroyRuntime: DestroyPassthruRuntimeFunction
    private let startRuntime: StartPassthruRuntimeFunction
    private let tryReceiveOutputFunction: TryReceivePassthruOutputFunction
    private let sendInputFunction: SendPassthruInputFunction

    fileprivate init(
        bridgeHandle: UnsafeMutableRawPointer,
        runtimeHandle: UnsafeMutableRawPointer,
        destroyRuntime: @escaping DestroyPassthruRuntimeFunction,
        startRuntime: @escaping StartPassthruRuntimeFunction,
        tryReceiveOutputFunction: @escaping TryReceivePassthruOutputFunction,
        sendInputFunction: @escaping SendPassthruInputFunction
    ) {
        self.bridgeHandle = bridgeHandle
        self.runtimeHandle = runtimeHandle
        self.destroyRuntime = destroyRuntime
        self.startRuntime = startRuntime
        self.tryReceiveOutputFunction = tryReceiveOutputFunction
        self.sendInputFunction = sendInputFunction
    }

    deinit {
        destroyRuntime(runtimeHandle)
        dlclose(bridgeHandle)
    }

    public func start() -> Result<Void, KanataHostBridgePassthruStartError> {
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)
        let started = startRuntime(runtimeHandle, &errorBuffer, errorBuffer.count)
        if started {
            return .success(())
        }
        return .failure(
            .failed(reason: Self.decodeCStringBuffer(errorBuffer) ?? "unknown passthru runtime start error")
        )
    }

    public func tryReceiveOutput() -> Result<KanataHostBridgePassthruOutputEvent?, KanataHostBridgePassthruReceiveError> {
        var value: UInt64 = 0
        var usagePage: UInt32 = 0
        var usage: UInt32 = 0
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)

        let result = tryReceiveOutputFunction(
            runtimeHandle,
            &value,
            &usagePage,
            &usage,
            &errorBuffer,
            errorBuffer.count
        )

        switch result {
        case 1:
            return .success(
                KanataHostBridgePassthruOutputEvent(
                    value: value,
                    usagePage: usagePage,
                    usage: usage
                )
            )
        case 0:
            return .success(nil)
        default:
            return .failure(
                .failed(reason: Self.decodeCStringBuffer(errorBuffer) ?? "unknown passthru output receive error")
            )
        }
    }

    public func sendInput(
        value: UInt64,
        usagePage: UInt32,
        usage: UInt32
    ) -> Result<Void, KanataHostBridgePassthruSendInputError> {
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)
        let sent = sendInputFunction(
            runtimeHandle,
            value,
            usagePage,
            usage,
            &errorBuffer,
            errorBuffer.count
        )
        if sent {
            return .success(())
        }

        return .failure(
            .failed(reason: Self.decodeCStringBuffer(errorBuffer) ?? "unknown passthru send-input error")
        )
    }

    private static func decodeCStringBuffer(_ buffer: [CChar]) -> String? {
        let bytes = buffer.map(UInt8.init(bitPattern:))
        let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let decoded = String(decoding: bytes[..<endIndex], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }
}

public enum KanataHostBridge {
    private static let rootOnlyVHIDDirectory = KeyPathConstants.VirtualHID.rootOnlyTmp
    private typealias VersionFunction = @convention(c) () -> UnsafePointer<CChar>?
    private typealias DefaultCfgCountFunction = @convention(c) () -> UInt
    private typealias ValidateConfigFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias CreateRuntimeFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> UnsafeMutableRawPointer?
    private typealias RunRuntimeFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UInt16,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias RuntimeLayerCountFunction = @convention(c) (UnsafeRawPointer?) -> Int
    private typealias DestroyRuntimeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CreatePassthruRuntimeFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UInt16,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> UnsafeMutableRawPointer?
    private typealias PassthruRuntimeLayerCountFunction = @convention(c) (UnsafeRawPointer?) -> Int
    private typealias DestroyPassthruRuntimeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias StartPassthruRuntimeFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias SendPassthruInputFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UInt32,
        UInt32,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias TryReceivePassthruOutputFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt64>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Int32

    public static func probe(
        runtimeHost: KanataRuntimeHost,
        fileManager: FileManager = .default
    ) -> KanataHostBridgeProbeResult {
        let path = runtimeHost.bridgeLibraryPath
        guard fileManager.fileExists(atPath: path) else {
            return .unavailable(reason: "library not found at \(path)")
        }

        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let error = dlerror().map { String(cString: $0) } ?? "unknown error"
            return .unavailable(reason: "failed to load \(path): \(error)")
        }
        defer { dlclose(handle) }

        guard let versionSymbol = dlsym(handle, "keypath_kanata_bridge_version"),
              let cfgCountSymbol = dlsym(handle, "keypath_kanata_bridge_default_cfg_count")
        else {
            let error = dlerror().map { String(cString: $0) } ?? "missing expected symbols"
            return .unavailable(reason: error)
        }

        let bridgeVersion = unsafeBitCast(versionSymbol, to: VersionFunction.self)()
            .map { String(cString: $0) } ?? "unknown"
        let defaultCfgCount = Int(unsafeBitCast(cfgCountSymbol, to: DefaultCfgCountFunction.self)())
        return .loaded(version: bridgeVersion, defaultConfigCount: defaultCfgCount)
    }

    public static func validateConfig(
        runtimeHost: KanataRuntimeHost,
        configPath: String,
        fileManager: FileManager = .default
    ) -> KanataHostBridgeValidationResult {
        guard let handle = openBridge(runtimeHost: runtimeHost, fileManager: fileManager) else {
            return .unavailable(reason: unavailableReason(runtimeHost: runtimeHost, fileManager: fileManager))
        }
        defer { dlclose(handle) }

        guard let validateSymbol = dlsym(handle, "keypath_kanata_bridge_validate_config") else {
            let error = dlerror().map { String(cString: $0) } ?? "missing validate symbol"
            return .unavailable(reason: error)
        }

        let validate = unsafeBitCast(validateSymbol, to: ValidateConfigFunction.self)
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)
        let success = configPath.withCString { configCString in
            validate(configCString, &errorBuffer, errorBuffer.count)
        }

        if success {
            return .valid
        }

        let reason = errorBuffer.withUnsafeBufferPointer { buffer in
            let bytes = buffer.map(UInt8.init(bitPattern:))
            let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex
            return String(decoding: bytes[..<endIndex], as: UTF8.self)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty {
            return .invalid(reason: "unknown validation error")
        }
        return .invalid(reason: reason)
    }

    public static func createRuntime(
        runtimeHost: KanataRuntimeHost,
        configPath: String,
        fileManager: FileManager = .default
    ) -> KanataHostBridgeRuntimeResult {
        guard let handle = openBridge(runtimeHost: runtimeHost, fileManager: fileManager) else {
            return .unavailable(reason: unavailableReason(runtimeHost: runtimeHost, fileManager: fileManager))
        }
        defer { dlclose(handle) }

        guard let createSymbol = dlsym(handle, "keypath_kanata_bridge_create_runtime"),
              let layerCountSymbol = dlsym(handle, "keypath_kanata_bridge_runtime_layer_count"),
              let destroySymbol = dlsym(handle, "keypath_kanata_bridge_destroy_runtime")
        else {
            let error = dlerror().map { String(cString: $0) } ?? "missing runtime symbols"
            return .unavailable(reason: error)
        }

        let createRuntime = unsafeBitCast(createSymbol, to: CreateRuntimeFunction.self)
        let runtimeLayerCount = unsafeBitCast(layerCountSymbol, to: RuntimeLayerCountFunction.self)
        let destroyRuntime = unsafeBitCast(destroySymbol, to: DestroyRuntimeFunction.self)
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)

        let runtime = configPath.withCString { configCString in
            createRuntime(configCString, &errorBuffer, errorBuffer.count)
        }

        guard let runtime else {
            return .failed(reason: decodeCStringBuffer(errorBuffer) ?? "unknown runtime creation error")
        }
        defer { destroyRuntime(runtime) }

        return .created(layerCount: runtimeLayerCount(runtime))
    }

    public static func runRuntime(
        runtimeHost: KanataRuntimeHost,
        configPath: String,
        tcpPort: UInt16,
        fileManager: FileManager = .default
    ) -> KanataHostBridgeRunResult {
        if let preflightFailure = preflightRunRuntime(fileManager: fileManager) {
            return preflightFailure
        }

        guard let handle = openBridge(runtimeHost: runtimeHost, fileManager: fileManager) else {
            return .unavailable(reason: unavailableReason(runtimeHost: runtimeHost, fileManager: fileManager))
        }
        defer { dlclose(handle) }

        guard let runSymbol = dlsym(handle, "keypath_kanata_bridge_run_runtime") else {
            let error = dlerror().map { String(cString: $0) } ?? "missing run-runtime symbol"
            return .unavailable(reason: error)
        }

        let runRuntime = unsafeBitCast(runSymbol, to: RunRuntimeFunction.self)
        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)
        let success = configPath.withCString { configCString in
            runRuntime(configCString, tcpPort, &errorBuffer, errorBuffer.count)
        }

        if success {
            return .completed
        }

        return .failed(reason: decodeCStringBuffer(errorBuffer) ?? "unknown runtime failure")
    }

    public static func createPassthruRuntime(
        runtimeHost: KanataRuntimeHost,
        configPath: String,
        tcpPort: UInt16,
        fileManager: FileManager = .default
    ) -> (
        result: KanataHostBridgePassthruRuntimeResult,
        handle: KanataHostBridgePassthruRuntimeHandle?
    ) {
        guard let bridgeHandle = openBridge(runtimeHost: runtimeHost, fileManager: fileManager) else {
            return (
                .unavailable(reason: unavailableReason(runtimeHost: runtimeHost, fileManager: fileManager)),
                nil
            )
        }

        guard let createSymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_create_passthru_runtime"),
              let layerCountSymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_passthru_runtime_layer_count"),
              let startSymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_start_passthru_runtime"),
              let sendInputSymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_passthru_send_input"),
              let tryReceiveSymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_passthru_try_recv_output"),
              let destroySymbol = dlsym(bridgeHandle, "keypath_kanata_bridge_destroy_passthru_runtime")
        else {
            let error = dlerror().map { String(cString: $0) } ?? "missing passthru runtime symbols"
            dlclose(bridgeHandle)
            return (.unavailable(reason: error), nil)
        }

        let createRuntime = unsafeBitCast(createSymbol, to: CreatePassthruRuntimeFunction.self)
        let runtimeLayerCount = unsafeBitCast(layerCountSymbol, to: PassthruRuntimeLayerCountFunction.self)
        let startRuntime = unsafeBitCast(startSymbol, to: StartPassthruRuntimeFunction.self)
        let sendInput = unsafeBitCast(sendInputSymbol, to: SendPassthruInputFunction.self)
        let tryReceiveOutput = unsafeBitCast(tryReceiveSymbol, to: TryReceivePassthruOutputFunction.self)
        let destroyRuntime = unsafeBitCast(destroySymbol, to: DestroyPassthruRuntimeFunction.self)

        var errorBuffer = Array<CChar>(repeating: 0, count: 2048)
        let runtimeHandle = configPath.withCString { configCString in
            createRuntime(configCString, tcpPort, &errorBuffer, errorBuffer.count)
        }

        guard let runtimeHandle else {
            let reason = decodeCStringBuffer(errorBuffer) ?? "unknown passthru runtime creation error"
            dlclose(bridgeHandle)
            return (.failed(reason: reason), nil)
        }

        let handle = KanataHostBridgePassthruRuntimeHandle(
            bridgeHandle: bridgeHandle,
            runtimeHandle: runtimeHandle,
            destroyRuntime: destroyRuntime,
            startRuntime: startRuntime,
            tryReceiveOutputFunction: tryReceiveOutput,
            sendInputFunction: sendInput
        )
        return (.created(layerCount: runtimeLayerCount(runtimeHandle)), handle)
    }

    private static func preflightRunRuntime(
        fileManager: FileManager
    ) -> KanataHostBridgeRunResult? {
        guard geteuid() != 0 else {
            return nil
        }

        guard fileManager.fileExists(atPath: rootOnlyVHIDDirectory) else {
            return nil
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: rootOnlyVHIDDirectory),
              let ownerID = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return .failed(
                reason: "could not inspect vhid driver socket directory at \(rootOnlyVHIDDirectory)"
            )
        }

        let isRootOwned = ownerID.intValue == 0
        let isRootOnly = permissions.intValue & 0o077 == 0
        if isRootOwned && isRootOnly {
            return .failed(
                reason: "vhid driver socket directory is root-only at \(rootOnlyVHIDDirectory); bundled host runtime needs a privileged output bridge"
            )
        }

        return nil
    }

    private static func openBridge(
        runtimeHost: KanataRuntimeHost,
        fileManager: FileManager
    ) -> UnsafeMutableRawPointer? {
        let path = runtimeHost.bridgeLibraryPath
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        return dlopen(path, RTLD_NOW | RTLD_LOCAL)
    }

    private static func unavailableReason(
        runtimeHost: KanataRuntimeHost,
        fileManager: FileManager
    ) -> String {
        let path = runtimeHost.bridgeLibraryPath
        if !fileManager.fileExists(atPath: path) {
            return "library not found at \(path)"
        }
        return "failed to load \(path): \(dlerror().map { String(cString: $0) } ?? "unknown error")"
    }

    private static func decodeCStringBuffer(_ buffer: [CChar]) -> String? {
        let bytes = buffer.map(UInt8.init(bitPattern:))
        let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let decoded = String(decoding: bytes[..<endIndex], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }
}
