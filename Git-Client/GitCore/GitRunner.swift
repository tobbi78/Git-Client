//
//  GitRunner.swift
//  Git-Client
//
//  Führt git-Kommandos als Subprozess aus und liefert das Ergebnis async zurück.
//  `run`/`runOrThrow` sind bewusst `nonisolated` — mehrere gleichzeitige Aufrufe
//  laufen parallel statt seriell durch den Actor-Executor (siehe Kommentar an `run`).
//  `actor` bleibt hier nur als Kapselung für `.shared`/`gitPath`, nicht zur Serialisierung.
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
    ///
    /// `nonisolated`, damit der Aufruf NICHT auf dem seriellen Actor-Executor läuft:
    /// sonst würde ein einzelner langsamer Aufruf (z.B. ein `fetch` beim Auto-Refresh-
    /// Polling, 10-60s) jeden anderen Git-Aufruf der App für seine gesamte Laufzeit
    /// blockieren, da `waitUntilExit()`/`group.wait()` unten synchron blockieren.
    /// Ohne `nonisolated` wäre das der Actor-Executor selbst — mit `nonisolated` ist es
    /// nur der dedizierte GCD-Block, den mehrere gleichzeitige Aufrufe unabhängig
    /// voneinander bekommen (echte Parallelität statt Serialisierung durch den Actor).
    ///
    /// Bewusster Trade-off: zwei schreibende git-Kommandos (checkout/fetch/clone) auf
    /// demselben Repo können jetzt exakt gleichzeitig laufen; trifft das ein, lässt
    /// Gits eigenes Datei-Lock (.git/index.lock) eines der beiden regulär fehlschlagen
    /// (via GitError.nonZeroExit bereits abgefangen). Kein neues Risiko — die
    /// Actor-Serialisierung garantierte nie eine sinnvolle Aufruf-Reihenfolge.
    nonisolated func run(_ arguments: [String], workingDirectory: URL? = nil) async throws -> GitResult {
        guard FileManager.default.fileExists(atPath: gitPath) else {
            throw GitError.gitNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Liest stdout/stderr parallel in Background-Threads, damit der Pipe-Buffer
            // (macOS: ~64 KB) nicht vollläuft. Ohne paralleles Lesen blockiert git bei
            // großen Ausgaben (z.B. git log auf einem großen Repo), wartet auf das
            // Leeren des Buffers — und waitUntilExit() kehrt nie zurück (Deadlock).
            //
            // Bewusst auf dedizierten DispatchQueue.global-Threads statt via `async let`/
            // Task: das hier ist echtes blockierendes I/O (readDataToEndOfFile,
            // waitUntilExit, group.wait). Auf Swifts kooperativem Thread-Pool ausgeführt,
            // erschöpft blockierendes I/O bei genug gleichzeitigen GitRunner-Aufrufen
            // (z.B. Testsuite mit paralleler withTaskGroup-Nutzung) den Pool und friert
            // die App/Tests ein — ausprobiert und wieder verworfen (siehe Git-Historie).
            //
            // QoS bewusst `.userInitiated` (nicht `.utility`): verhindert die
            // Prioritätsinversion, die entstand, wenn ein Aufrufer mit höherer QoS
            // hier auf niedriger priorisierte Reader-Threads wartete (Xcode Runtime
            // Issue). `.userInitiated` passt zu den tatsächlichen Aufrufern (UI-nahe
            // ViewModel-Actions), ist aber weiterhin niedriger als `.userInteractive`.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.gitPath)
                process.arguments = arguments

                if let workingDirectory {
                    process.currentDirectoryURL = workingDirectory
                }

                // Verhindert, dass git bei fehlenden Credentials interaktiv nach einem
                // Passwort fragt (würde den Prozess hängen lassen). Für eine GUI-App immer
                // sinnvoll; ohne diesen Schutz würde ls-remote/fetch an einem Prompt hängen.
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                // Lesende Befehle (v.a. `git status` beim Auto-Refresh/FSEvent-Polling)
                // schreiben sonst opportunistisch den Index neu und legen dafür
                // `.git/index.lock` an. Läuft parallel ein Fetch/Checkout, scheitert einer
                // von beiden mit "Unable to create index.lock: File exists". Mit "0"
                // überspringen reine Lesebefehle diesen Schreibversuch; schreibende
                // Befehle sperren weiterhin regulär.
                env["GIT_OPTIONAL_LOCKS"] = "0"
                // Eine per Doppelklick/Dock gestartete GUI-App erbt NICHT die Shell-Profile
                // (.zprofile/.zshrc) und damit auch nicht deren PATH-Ergänzungen — anders als
                // ein aus dem Terminal gestartetes git. Befehle, die git über PATH aufgerufene
                // externe Helper benötigen (z.B. `git-lfs filter-process` bei LFS-Repos),
                // schlagen dadurch in der gebauten App fehl, obwohl sie im Terminal
                // funktionieren (beobachtet: "git-lfs: command not found" trotz installiertem
                // git-lfs). Gängige Installationsorte werden deshalb explizit ergänzt.
                env["PATH"] = GitRunner.augmentedPath(current: env["PATH"])
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

                let group = DispatchGroup()
                let stdoutCollector = DataCollector()
                let stderrCollector = DataCollector()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutCollector.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
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
    }

    /// Kurzform: wirft GitError.nonZeroExit bei exitCode != 0, gibt stdout zurück.
    /// Discardable, da mehrere Aufrufer (clone, fetch, fastForward) nur am Erfolg/
    /// Fehler interessiert sind, nicht am stdout-Inhalt.
    @discardableResult
    nonisolated func runOrThrow(_ arguments: [String], workingDirectory: URL? = nil) async throws -> String {
        let result = try await run(arguments, workingDirectory: workingDirectory)
        guard result.exitCode == 0 else {
            throw GitError.nonZeroExit(code: result.exitCode, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    /// Ergänzt `current` um gängige Homebrew-/Standard-Installationsorte, falls sie
    /// dort noch nicht enthalten sind. Eigene, pure Funktion statt Inline-Logik in
    /// `run` — testbar ohne echten Prozess/Environment.
    nonisolated static func augmentedPath(current: String?) -> String {
        let fallback = "/usr/bin:/bin:/usr/sbin:/sbin"
        let base = current ?? fallback
        let existing = Set(base.split(separator: ":").map(String.init))
        let extras = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
            .filter { !existing.contains($0) }
        guard !extras.isEmpty else { return base }
        return (extras + [base]).joined(separator: ":")
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
