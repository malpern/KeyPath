import Foundation
import KeyPathCore
import Security

/// A set of strings kept in one login-Keychain item that only KeyPath can read
/// without asking the user. Unlike UserDefaults, another process cannot add to
/// it silently, so it holds the user's security choices.
@MainActor
final class KeychainStringSet {
    private let service: String
    private let account: String
    private var cache: Set<String>?

    init(service: String = "com.keypath.app", account: String) {
        self.service = service
        self.account = account
    }

    var members: Set<String> {
        load()
    }

    /// Adds a member. Returns false, and changes nothing, when the Keychain refuses the write.
    @discardableResult
    func insert(_ member: String) -> Bool {
        // Writing after a failed read would replace the stored set with one member.
        guard var next = loadForWrite() else { return false }
        guard next.insert(member).inserted else { return true }
        return save(next)
    }

    /// Removes a member. Returns false, and changes nothing, when the Keychain refuses the write.
    @discardableResult
    func remove(_ member: String) -> Bool {
        guard var next = loadForWrite() else { return false }
        guard next.remove(member) != nil else { return true }
        return save(next)
    }

    /// Removes the item. Returns false, and keeps the cached members, when the Keychain refuses.
    @discardableResult
    func removeAll() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            AppLogger.shared.log("⚠️ [Keychain] Could not delete \(account) (status \(status))")
            return false
        }
        cache = []
        return true
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The stored members, or nil when the Keychain could not be read.
    private func loadForWrite() -> Set<String>? {
        let members = load()
        return lastReadFailed ? nil : members
    }

    private var lastReadFailed = false

    /// A failed read is not cached, so the next read tries again.
    private func load() -> Set<String> {
        if let cache { return cache }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        var members: Set<String> = []
        if status == errSecSuccess, let data = result as? Data,
           let list = try? JSONDecoder().decode([String].self, from: data)
        {
            members = Set(list)
        } else if status != errSecItemNotFound {
            AppLogger.shared.log("⚠️ [Keychain] Could not read \(account) (status \(status))")
            lastReadFailed = true
            return []
        }
        lastReadFailed = false
        cache = members
        return members
    }

    private func save(_ members: Set<String>) -> Bool {
        guard let data = try? JSONEncoder().encode(members.sorted()) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            AppLogger.shared.log("⚠️ [Keychain] Could not save \(account) (status \(status))")
            return false
        }
        cache = members
        return true
    }
}
