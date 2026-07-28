import Foundation
import Security

enum ManusAPIKeyStoreError: Error, Equatable, Sendable {
    case invalidCredential
    case missingCredential
    case keychainLocked
    case accessDenied
    case unavailable
    case invalidStoredCredential
}

enum ManusCredentialConfigurationState: Equatable, Sendable {
    case notConfigured
    case configured
    case unavailable(ManusAPIKeyStoreError)
}

struct ManusKeychainQueryContract: Equatable, Sendable {
    let itemClass: String?
    let service: String?
    let account: String?
    let accessibility: String?
    let synchronizable: Bool?
    let usesDataProtectionKeychain: Bool?
}

protocol ManusAPIKeyStoring: Sendable {
    func configurationState() async -> ManusCredentialConfigurationState
    func read() async throws -> String
    func save(_ credential: String) async throws
    func delete() async throws
}

extension ManusAPIKeyStoring {
    func isConfigured() async -> Bool {
        await configurationState() == .configured
    }
}

actor ManusAPIKeyStore: ManusAPIKeyStoring {
    static let productionService =
        "com.kevinchen.CodexUsageMonitor.manus-api-v2"
    static let productionAccount = "primary"
    static let productionAccessibility =
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    static let productionSynchronizable = false

    let service: String
    let account: String
    nonisolated let usesDataProtectionKeychain: Bool

    init(
        service: String = productionService,
        account: String = productionAccount,
        usesDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.account = account
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    func configurationState() -> ManusCredentialConfigurationState {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return .configured
        case errSecItemNotFound:
            return .notConfigured
        default:
            return .unavailable(Self.error(for: status))
        }
    }

    func read() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw Self.error(for: status)
        }
        guard let data = result as? Data,
              let credential = String(data: data, encoding: .utf8),
              Self.isValid(credential) else {
            throw ManusAPIKeyStoreError.invalidStoredCredential
        }
        return credential
    }

    func save(_ credential: String) throws {
        guard Self.isValid(credential),
              let data = credential.data(using: .utf8) else {
            throw ManusAPIKeyStoreError.invalidCredential
        }
        var add = baseQuery()
        add[kSecAttrAccessible as String] =
            Self.productionAccessibility
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String:
                    Self.productionAccessibility,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                attributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw Self.error(for: updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw Self.error(for: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.error(for: status)
        }
    }

    func queryContract() -> ManusKeychainQueryContract {
        let query = baseQuery()
        return ManusKeychainQueryContract(
            itemClass: query[kSecClass as String] as? String,
            service: query[kSecAttrService as String] as? String,
            account: query[kSecAttrAccount as String] as? String,
            accessibility: query[kSecAttrAccessible as String] as? String,
            synchronizable:
                query[kSecAttrSynchronizable as String] as? Bool,
            usesDataProtectionKeychain:
                query[kSecUseDataProtectionKeychain as String] as? Bool
        )
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String:
                Self.productionAccessibility,
            kSecAttrSynchronizable as String:
                Self.productionSynchronizable,
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func isValid(_ credential: String) -> Bool {
        !credential.isEmpty
            && credential.utf8.count <= 4_096
            && !credential.contains(where: \.isNewline)
    }

    private static func error(for status: OSStatus) -> ManusAPIKeyStoreError {
        switch status {
        case errSecItemNotFound:
            .missingCredential
        case errSecInteractionNotAllowed:
            .keychainLocked
        case errSecAuthFailed, errSecUserCanceled:
            .accessDenied
        default:
            .unavailable
        }
    }
}
