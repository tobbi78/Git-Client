//
//  KeychainStore.swift
//  Git-Client
//
//  Speichert und liest HTTPS-Credentials (Passwort/Token) pro Repository
//  im macOS System-Keychain.
//
//  Sicherheitsregeln (dürfen NICHT gebrochen werden):
//  - Passwörter/Tokens werden NIEMALS in bookmarks.json gespeichert.
//  - Jeder Eintrag ist strikt an eine bookmark.id (UUID) gebunden.
//  - Es gibt keine host-basierten oder geteilten Credentials.
//

import Foundation
import Security

enum KeychainStore {

    // Keychain-Service-Label: identifiziert alle Einträge dieser App.
    private static let service = "de.tobias.florian.Git-Client.credentials"

    /// Speichert `secret` für `id`. Überschreibt ggf. vorhandenen Eintrag.
    static func save(_ secret: String, for id: UUID) {
        let data = Data(secret.utf8)
        let query = baseQuery(for: id)

        // Zuerst löschen (falls vorhanden), dann neu anlegen — sicherster Weg.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Liest das gespeicherte Secret für `id`. Gibt `nil` zurück wenn keins vorhanden.
    static func load(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8)
        else { return nil }
        return secret
    }

    /// Löscht das gespeicherte Secret für `id`.
    static func delete(for id: UUID) {
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    // MARK: - Privat

    private static func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
