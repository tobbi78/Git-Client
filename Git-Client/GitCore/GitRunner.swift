//
//  GitRunner.swift
//  Git-Client
//
//  Führt git-Kommandos als Subprozess aus und liefert das Ergebnis async zurück.
//  Isoliert als actor, damit mehrere gleichzeitige Aufrufe serialisiert werden.
//

import Foundation

struct GitResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

actor GitRunner {
    static let shared = GitRunner()

    private let gitPath: String

    private init() {
        // /usr/bin/git ist Apples Shim, der das installierte git der Command Line Tools nutzt.
        gitPath = "/usr/bin/git"
    }

    /// Führt git mit den gegebenen Argumenten im angegebenen Verzeichnis aus.
    func run(_ arguments: [String], workingDirectory: URL? = nil) async throws -> GitResult {
        guard FileManager.default.fileExists(atPath: gitPath) else {
            throw GitError.gitNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments

            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            continuation.resume(returning: GitResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            ))
        }
    }

    /// Kurzform: wirft GitError.nonZeroExit bei exitCode != 0, gibt stdout zurück.
    func runOrThrow(_ arguments: [String], workingDirectory: URL? = nil) async throws -> String {
        let result = try await run(arguments, workingDirectory: workingDirectory)
        guard result.exitCode == 0 else {
            throw GitError.nonZeroExit(code: result.exitCode, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }
}
