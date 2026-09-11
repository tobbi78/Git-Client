//
//  BookmarkStore.swift
//  Git-Client
//
//  Lädt und speichert den BookmarkNode-Baum als JSON in Application Support.
//  Atomar via temporäre Datei + rename, damit kein halbgeschriebener Zustand entstehen kann.
//

import Foundation

final class BookmarkStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Git-Client", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [BookmarkNode] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([BookmarkNode].self, from: data)) ?? []
    }

    func save(_ nodes: [BookmarkNode]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(nodes) else { return }

        // Atomares Schreiben: in temp-Datei schreiben, dann umbenennen
        let tmp = fileURL.appendingPathExtension("tmp")
        try? data.write(to: tmp, options: .atomic)
        try? FileManager.default.replaceItem(
            at: fileURL,
            withItemAt: tmp,
            backupItemName: nil,
            resultingItemURL: nil
        )
    }
}
