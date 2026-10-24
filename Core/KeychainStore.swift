import Foundation
import Security

public protocol CredentialsStoring: Sendable {
    func loadClientKey(forHost host: String) -> String?
    func saveClientKey(_ key: String, forHost host: String) throws
    func deleteClientKey(forHost host: String) throws

    func loadLastHost() -> String?
    func saveLastHost(_ host: String?)

    func loadTVMACAddress() -> String?
    func saveTVMACAddress(_ mac: String?)
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

public final class KeychainStore: CredentialsStoring, @unchecked Sendable {
    public static let shared = KeychainStore()

    private let service: String
    private let defaults: UserDefaults
    private let lastHostKey = "com.lgchannelsearch.lastTVHost"
    private let tvMACKey = "com.lgchannelsearch.tvMACAddress"

    public init(
        service: String = "com.lgchannelsearch.ssap.clientkey",
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    public func loadClientKey(forHost host: String) -> String? {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedHost,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8),
           !key.isEmpty {
            return key
        }
        #if targetEnvironment(simulator)
        if let fallback = defaults.string(forKey: "\(service).\(normalizedHost)"),
           !fallback.isEmpty {
            return fallback
        }
        #endif
        #if DEBUG
        if let envKey = ProcessInfo.processInfo.environment["LG_TV_CLIENT_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            try? saveClientKey(envKey, forHost: normalizedHost)
            return envKey
        }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--client-key-file"), idx + 1 < args.count {
            let filePath = args[idx + 1]
            if let data = FileManager.default.contents(atPath: filePath),
               let fileKey = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fileKey.isEmpty {
                try? saveClientKey(fileKey, forHost: normalizedHost)
                return fileKey
            }
        }
        #endif
        return nil
    }

    public func saveClientKey(_ key: String, forHost host: String) throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return }
        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedHost
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            #if targetEnvironment(simulator)
            if addStatus == -34018 { // errSecMissingEntitlement on unsigned Simulator builds
                defaults.set(key, forKey: "\(service).\(normalizedHost)")
                return
            }
            #endif
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            #if targetEnvironment(simulator)
            if updateStatus == -34018 {
                defaults.set(key, forKey: "\(service).\(normalizedHost)")
                return
            }
            #endif
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func deleteClientKey(forHost host: String) throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return }
        #if targetEnvironment(simulator)
        defaults.removeObject(forKey: "\(service).\(normalizedHost)")
        #endif

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedHost
        ]

        let status = SecItemDelete(query as CFDictionary)
        #if targetEnvironment(simulator)
        if status == -34018 { return }
        #endif
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func loadLastHost() -> String? {
        if let value = defaults.string(forKey: lastHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        #if DEBUG
        if let envHost = ProcessInfo.processInfo.environment["LG_TV_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envHost.isEmpty {
            saveLastHost(envHost)
            return envHost
        }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--tv-host"), idx + 1 < args.count {
            let argHost = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !argHost.isEmpty {
                saveLastHost(argHost)
                return argHost
            }
        }
        #endif
        return nil
    }

    public func saveLastHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: lastHostKey)
        } else {
            defaults.removeObject(forKey: lastHostKey)
        }
    }

    public func loadTVMACAddress() -> String? {
        let value = defaults.string(forKey: tvMACKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    public func saveTVMACAddress(_ mac: String?) {
        let trimmed = mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: tvMACKey)
        } else {
            defaults.removeObject(forKey: tvMACKey)
        }
    }
}

/// Thread-safe in-memory credentials store for unit tests and mock mode.
public final class InMemoryCredentialsStore: CredentialsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keysByHost: [String: String] = [:]
    private var lastHost: String?
    private var macAddress: String?

    public init(lastHost: String? = nil, macAddress: String? = nil, keysByHost: [String: String] = [:]) {
        self.lastHost = lastHost
        self.macAddress = macAddress
        self.keysByHost = keysByHost
    }

    public func loadClientKey(forHost host: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keysByHost[host.lowercased()]
    }

    public func saveClientKey(_ key: String, forHost host: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keysByHost[host.lowercased()] = key
    }

    public func deleteClientKey(forHost host: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keysByHost.removeValue(forKey: host.lowercased())
    }

    public func loadLastHost() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastHost
    }

    public func saveLastHost(_ host: String?) {
        lock.lock()
        defer { lock.unlock() }
        lastHost = host
    }

    public func loadTVMACAddress() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return macAddress
    }

    public func saveTVMACAddress(_ mac: String?) {
        lock.lock()
        defer { lock.unlock() }
        macAddress = mac
    }
}
