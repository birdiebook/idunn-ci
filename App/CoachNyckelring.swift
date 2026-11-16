import Foundation
import Security
import Coach

/// BESLUT B127 · METOD M73
/// Kopplingen till coachen i telefonens nyckelring: värden, nyckeln och telefonens hemlighet. Den går att läsa när
/// telefonen låsts upp en gång efter en omstart (så att en sändning i bakgrunden fungerar) och följer inte med till
/// en annan telefon eller en säkerhetskopia: en ny telefon kopplas på nytt.
enum CoachNyckelring {
    private static let tjänst: String = "se.birdiebook.idun.coach"
    private static let konto: String = "koppling"

    private static var grund: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjänst,
            kSecAttrAccount as String: konto,
        ]
    }

    /// Den sparade kopplingen, eller `nil` när telefonen inte är kopplad (eller det sparade inte längre är giltigt).
    static func läs() -> CoachConfig? {
        var fråga: [String: Any] = grund
        fråga[kSecReturnData as String] = true
        fråga[kSecMatchLimit as String] = kSecMatchLimitOne
        var ut: CFTypeRef?
        guard SecItemCopyMatching(fråga as CFDictionary, &ut) == errSecSuccess, let data = ut as? Data,
              let c = try? JSONDecoder().decode(CoachConfig.self, from: data), c.isValid else {
            return nil
        }
        return c
    }

    /// Sparar kopplingen (och ersätter en äldre). `false` när nyckelringen sa nej.
    @discardableResult
    static func spara(_ c: CoachConfig) -> Bool {
        guard let data = try? JSONEncoder().encode(c) else { return false }
        taBort()
        var ny: [String: Any] = grund
        ny[kSecValueData as String] = data
        ny[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(ny as CFDictionary, nil) == errSecSuccess
    }

    static func taBort() {
        SecItemDelete(grund as CFDictionary)
    }
}
