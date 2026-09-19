//
//  ClipboardService.swift
//  Git-Client
//
//  Dünner Wrapper um NSPasteboard für Kopieren-Aktionen (SHA, Branch-/Tag-Name,
//  Commit-Nachricht) aus Kontextmenüs heraus.
//

import AppKit

enum ClipboardService {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
