import Foundation
import MessagingDomain
import Security

/// `SessionStore` in the login Keychain, as a generic password readable only on this Mac.
public struct KeychainSessionStore: SessionStore {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private let service: String
    private let account: String

    public init(service: String, account: String = "session") {
        self.service = service
        self.account = account
    }

    public func load() async throws -> SessionData? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return (result as? Data).map(SessionData.init)
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    public func save(_ session: SessionData) async throws {
        let update = [kSecValueData as String: session.bytes] as CFDictionary
        let status = SecItemUpdate(baseQuery as CFDictionary, update)
        if status == errSecItemNotFound {
            try add(session)
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    private func add(_ session: SessionData) throws {
        var item = baseQuery
        item[kSecValueData as String] = session.bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
