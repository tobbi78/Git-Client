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

            // Verhindert, dass git bei fehlenden Credentials interaktiv nach einem
            // Passwort fragt (würde den Prozess hängen lassen). Für eine GUI-App immer
            // sinnvoll; ohne diesen Schutz würde ls-remote/fetch an einem Prompt hängen.
            var env = ProcessInfo.processInfo.environment
            env["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = env

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

            // Liest stdout/stderr parallel in Background-Threads, damit der Pipe-Buffer
            // (macOS: ~64 KB) nicht vollläuft. Ohne paralleles Lesen blockiert git bei
            // großen Ausgaben (z.B. git log auf einem großen Repo), wartet auf das
            // Leeren des Buffers — und waitUntilExit() kehrt nie zurück (Deadlock).
            let group = DispatchGroup()
            let stdoutCollector = DataCollector()
            let stderrCollector = DataCollector()

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutCollector.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrCollector.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.waitUntilExit()
            group.wait()

            let stdout = String(data: stdoutCollector.data, encoding: .utf8) ?? ""
            let stderr = String(data: stderrCollector.data, encoding: .utf8) ?? ""

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

// MARK: - Private Hilfswerkzeug

/// Sammelt Data für den DispatchGroup-basierten Pipe-Read.
/// @unchecked Sendable: Zugriff ist durch group.wait() sequenziert.
/// nonisolated, da kein MainActor-Kontext benötigt wird.
private final class DataCollector: @unchecked Sendable {
    nonisolated init() {}
    nonisolated(unsafe) var data = Data()
}

