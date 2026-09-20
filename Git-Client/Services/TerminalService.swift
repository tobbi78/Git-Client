//
//  TerminalService.swift
//  Git-Client
//
//  Öffnet einen Ordner in einer Terminal-App. Probiert eine Priorität bekannter
//  Terminal-Apps durch und fällt auf Terminal.app zurück, die auf jedem macOS
//  vorhanden ist.
//

import AppKit

nonisolated enum TerminalService {
    /// Terminal.app steht bewusst als letzter Eintrag — sie ist immer installiert
    /// und garantiert damit einen funktionierenden Fallback.
    static let preferredBundleIdentifiers: [String] = [
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.apple.Terminal",
    ]

    static func firstAvailable(in identifiers: [String], resolve: (String) -> URL?) -> URL? {
        for identifier in identifiers {
            if let url = resolve(identifier) {
                return url
            }
        }
        return nil
    }

    static func terminalApplicationURL() -> URL? {
        firstAvailable(in: preferredBundleIdentifiers) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    }

    static func open(directory: URL) {
        guard let terminalURL = terminalApplicationURL() else { return }
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
