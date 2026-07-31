import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case notFound(String)
    case unexpectedData
    case osError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound(let tag): "No keychain item found for tag \(tag)"
        case .unexpectedData: "Keychain item contained unexpected data"
        case .osError(let status):
            "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }
}

/// Stores private keys and SSH passwords as generic-password items under the
/// service `com.local.miniCA` — the same naming the original app used, so
/// existing entries remain readable.
enum KeychainService {
    static let service = "com.local.miniCA"

    static func keyTag(for id: UUID) -> String { "\(service).key.\(id.uuidString)" }
    static func sshTag(for id: UUID) -> String { "\(service).ssh.\(id.uuidString)" }

    static func store(data: Data, tag: String, label: String) throws {
        delete(tag: tag)
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag,
            kSecAttrLabel: label,
            kSecValueData: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osError(status) }
    }

    static func store(string: String, tag: String, label: String) throws {
        try store(data: Data(string.utf8), tag: tag, label: label)
    }

    static func loadData(tag: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeychainError.notFound(tag) }
        guard status == errSecSuccess else { throw KeychainError.osError(status) }
        guard let data = result as? Data else { throw KeychainError.unexpectedData }
        return data
    }

    static func loadString(tag: String) throws -> String {
        guard let s = String(data: try loadData(tag: tag), encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return s
    }

    @discardableResult
    static func delete(tag: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
