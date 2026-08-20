import Foundation
import Security

/// Diagnostic: can this app use the data-protection keychain?
///
/// Legacy file-based keychain items carry a per-item ACL pinned to the exact
/// code that created them, so every rebuild re-prompts. The data-protection
/// keychain has no such ACLs - access is governed by the signing identity - but
/// it normally requires an application-identifier entitlement, which a
/// self-signed build without a Team ID may not be able to claim.
///
/// This writes, reads back and deletes a dummy item, reporting raw OSStatus so
/// the answer is a fact rather than a guess.
enum KeychainSelfTest {
    private static let service = "app.youhaveameeting.selftest"

    static func run() -> String {
        var lines: [String] = []
        for useDataProtection in [false, true] {
            let label = useDataProtection ? "data-protection" : "legacy file-based"
            lines.append("\(label): \(probe(useDataProtection: useDataProtection))")
        }
        return lines.joined(separator: "\n")
    }

    private static func probe(useDataProtection: Bool) -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe"
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = Data("probe".utf8)
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            return "add failed (\(describe(addStatus)))"
        }

        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(read as CFDictionary, &item)
        SecItemDelete(query as CFDictionary)

        guard readStatus == errSecSuccess else {
            return "wrote, but read back failed (\(describe(readStatus)))"
        }
        return "usable"
    }

    private static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "OSStatus \(status): \(message)"
    }
}
