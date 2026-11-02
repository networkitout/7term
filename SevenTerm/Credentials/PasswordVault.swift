import Foundation
import LocalAuthentication
import Security

/// Saved host passwords, one generic-password item per host in the login
/// Keychain (service "com.networkitout.seventerm.ssh-password", account =
/// host id). Only 7 Term's own signed binary can read them without a
/// Keychain prompt, and 7 Term asks for Touch ID (or your Mac password)
/// before every read.
///
/// The passwords never touch the host database, the backup, or the logs.
enum PasswordVault {
    static let service = "com.networkitout.seventerm.ssh-password"

    enum VaultError: Error, LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
                return "Keychain: \(message)"
            }
        }
    }

    /// Stores or replaces the password for a host.
    static func save(_ password: String, hostID: String, label: String) throws {
        delete(hostID: hostID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
            kSecAttrLabel as String: "7 Term: \(label)",
            kSecAttrDescription as String: "SSH password",
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    static func delete(hostID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Whether a password is stored, without reading it (no Touch ID).
    static func exists(hostID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
            kSecReturnAttributes as String: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Asks for Touch ID (falling back to the Mac's password), then returns
    /// the stored password, or nil if the user cancels or nothing is stored.
    /// Blocks the calling thread while the system prompt is up.
    static func read(hostID: String, reason: String) -> String? {
        guard exists(hostID: hostID), authenticate(reason: reason) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Touch ID, Apple Watch, or the Mac password, via LocalAuthentication.
    private static func authenticate(reason: String) -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }

        final class Outcome: @unchecked Sendable { var approved = false }
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { approved, _ in
            outcome.approved = approved
            done.signal()
        }
        done.wait()
        return outcome.approved
    }
}
