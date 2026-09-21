//
//  GitError.swift
//  Git-Client
//

import Foundation

enum GitError: Error, LocalizedError {
    case gitNotFound
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "git wurde nicht gefunden. Bitte installiere die Xcode Command Line Tools."
        case .nonZeroExit(let code, let stderr):
            return "git beendete mit Code \(code): \(stderr)"
        }
    }
}
