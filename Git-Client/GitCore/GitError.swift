//
//  GitError.swift
//  Git-Client
//

import Foundation

enum GitError: Error, LocalizedError {
    case gitNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case indexLockInUse

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "git wurde nicht gefunden. Bitte installiere die Xcode Command Line Tools."
        case .nonZeroExit(let code, let stderr):
            return "git beendete mit Code \(code): \(stderr)"
        case .indexLockInUse:
            return "Die Sperrdatei wird gerade von einem laufenden Git-Prozess verwendet. Bitte kurz warten und erneut versuchen."
        }
    }

    /// true, wenn die Meldung eine bestehende `index.lock` meldet ("Unable to create …/index.lock: File exists").
    nonisolated static func isIndexLockMessage(_ message: String) -> Bool {
        message.contains("index.lock") && message.contains("File exists")
    }
}
