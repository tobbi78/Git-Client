//
//  GitFolderWatcher.swift
//  Git-Client
//
//  Überwacht eine Menge von `.git`-Verzeichnissen per FSEventStream und meldet
//  Änderungen als Set der betroffenen `.git`-URLs.
//
//  Bewusst kein Combine und kein Actor-Typ: FSEventStream-Callbacks laufen
//  auf einer DispatchQueue — der Hop auf den MainActor obliegt dem Aufrufer.
//

import Foundation
import CoreServices

/// Beobachtet beliebig viele `.git`-Verzeichnisse in **einem** FSEventStream.
/// Änderungen werden als `Set<URL>` der betroffenen `.git`-Roots gemeldet.
final class GitFolderWatcher: @unchecked Sendable {

    // MARK: - Typen

    /// Callback-Typ: liefert die betroffenen `.git`-Verzeichnis-URLs.
    typealias ChangeHandler = @Sendable (Set<URL>) -> Void

    // MARK: - Zustand (geschützt durch serialQueue)

    private var eventStream: FSEventStreamRef?
    private var watchedPaths: [URL] = []
    private var onChange: ChangeHandler?

    // Eigene serielle Queue für Zustandszugriffe
    private let serialQueue = DispatchQueue(label: "de.gitclient.GitFolderWatcher", qos: .utility)

    // MARK: - Init / Deinit

    init() {}

    deinit {
        stopStream()
    }

    // MARK: - Öffentliche API

    /// Startet (oder startet neu) den Watcher mit den angegebenen `.git`-Pfaden.
    /// Kann nach einem Bookmark-Update gerufen werden, um den Pfad-Set zu aktualisieren.
    func update(paths: [URL], onChange: @escaping ChangeHandler) {
        serialQueue.async { [weak self] in
            guard let self else { return }
            self.stopStream()
            self.watchedPaths = paths
            self.onChange = onChange
            guard !paths.isEmpty else { return }
            self.startStream()
        }
    }

    /// Stoppt den Watcher vollständig.
    func stop() {
        serialQueue.async { [weak self] in
            self?.stopStream()
        }
    }

    // MARK: - Interner Stream-Aufbau (auf serialQueue)

    private func startStream() {
        guard !watchedPaths.isEmpty else { return }

        // CFArray der Pfad-Strings aufbauen
        let pathStrings = watchedPaths.map { $0.path } as CFArray

        // C-Callback: Kontext zeigt auf `self`
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            gitFolderWatcherCallback,
            &context,
            pathStrings,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,   // Latenz in Sekunden (wirkt als Debounce)
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents
            )
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, serialQueue)
        FSEventStreamStart(stream)
        self.eventStream = stream
    }

    private func stopStream() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    // MARK: - Event-Verarbeitung (intern, auf serialQueue)

    /// Mappt die gemeldeten Dateipfade auf die überwachten `.git`-Roots
    /// und ruft `onChange` mit der betroffenen Teilmenge auf.
    fileprivate func handleEvents(paths: [String]) {
        let watched = watchedPaths
        var affected = Set<URL>()

        for eventPath in paths {
            for root in watched {
                // Ist der Event-Pfad innerhalb dieses .git-Verzeichnisses?
                if eventPath.hasPrefix(root.path) {
                    affected.insert(root)
                    break
                }
            }
        }

        guard !affected.isEmpty, let handler = onChange else { return }
        // Hop auf MainActor macht der Aufrufer (AppModel).
        handler(affected)
    }
}

// MARK: - C-Callback (Top-Level, kein Capture von self)

private func gitFolderWatcherCallback(
    _: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<GitFolderWatcher>.fromOpaque(info).takeUnretainedValue()

    // eventPaths *ist* das CFArray (kFSEventStreamCreateFlagUseCFTypes);
    // über Unmanaged korrekt als Swift-Array bridgen.
    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    guard let cfPaths = cfArray as? [String] else { return }

    watcher.handleEvents(paths: cfPaths)
}
