import Foundation
import Security
import LocalAuthentication

public final class KeychainManager {
    private let auth: Authenticating

    /// Use this initialiser in tests: injects a mock auth.
    init(auth: Authenticating) {
        self.auth = auth
    }

    /// Creates a production manager.
    public static func production(auth: Authenticating) -> KeychainManager {
        KeychainManager(auth: auth)
    }

    // MARK: - Read

    public func read(service: String, account: String) async throws -> String {
        let context = try await auth.authenticate(
            reason: "read password for '\(service)' (\(account))"
        )
        context.interactionNotAllowed = false

        let query: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecAttrService:              service,
            kSecAttrAccount:              account,
            kSecReturnData:               true,
            kSecUseAuthenticationContext: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:      break
        case errSecItemNotFound: throw AppError.itemNotFound
        default:                 throw AppError.keychainError(status)
        }

        guard var data = item as? Data else {
            throw AppError.keychainError(errSecDecode)
        }
        defer { data.resetBytes(in: 0..<data.count) }

        guard let password = String(data: data, encoding: .utf8) else {
            throw AppError.keychainError(errSecDecode)
        }
        return password
    }

    // MARK: - Write

    public func write(
        service: String,
        account: String,
        password: String,
        label: String
    ) async throws {
        let context = try await auth.authenticate(
            reason: "write password for '\(service)' (\(account))"
        )
        context.interactionNotAllowed = false

        guard var passwordData = password.data(using: .utf8) else {
            throw AppError.inputError("Password contains invalid UTF-8.")
        }
        defer { passwordData.resetBytes(in: 0..<passwordData.count) }

        let attributes: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecAttrService:              service,
            kSecAttrAccount:              account,
            kSecAttrLabel:                label,
            kSecAttrAccessible:           kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData:                passwordData,
            kSecUseAuthenticationContext: context,
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            let query: [CFString: Any] = [
                kSecClass:                    kSecClassGenericPassword,
                kSecAttrService:              service,
                kSecAttrAccount:              account,
                kSecUseAuthenticationContext: context,
            ]
            // kSecAttrAccessible is intentionally absent: accessibility cannot
            // be changed on an existing item via SecItemUpdate.
            let update: [CFString: Any] = [
                kSecAttrLabel:  label,
                kSecValueData:  passwordData,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw AppError.keychainError(addStatus)
        }
    }

    // MARK: - Delete

    public func delete(service: String, account: String) async throws {
        let context = try await auth.authenticate(
            reason: "delete password for '\(service)' (\(account))"
        )
        context.interactionNotAllowed = false

        let query: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecAttrService:              service,
            kSecAttrAccount:              account,
            kSecUseAuthenticationContext: context,
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess:      break
        case errSecItemNotFound: throw AppError.itemNotFound
        default:                 throw AppError.keychainError(status)
        }
    }

    // MARK: - List

    public func list(service: String?) async throws -> [KeychainEntry] {
        let reason = service.map { "list keychain entries for '\($0)'" }
            ?? "list keychain entries"
        let context = try await auth.authenticate(reason: reason)
        context.interactionNotAllowed = false

        var query: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecReturnAttributes:         true,
            kSecMatchLimit:               kSecMatchLimitAll,
            kSecUseAuthenticationContext: context,
        ]
        if let svc = service {
            query[kSecAttrService] = svc
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:      break
        case errSecItemNotFound: return []
        default:                 throw AppError.keychainError(status)
        }

        guard let items = item as? [[String: Any]] else { return [] }

        return items.compactMap { dict in
            guard
                let svc  = dict[kSecAttrService as String] as? String,
                let acct = dict[kSecAttrAccount as String] as? String
            else { return nil }
            return KeychainEntry(service: svc, account: acct)
        }
    }
}
