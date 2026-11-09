//
//  Bookmark.swift
//  Git-Client
//
//  Rekursiver Lesezeichen-Baum: Ordner und Repository-Einträge, beliebig verschachtelbar.
//  Codable für JSON-Persistenz, Identifiable/Hashable für SwiftUI-Listen.
//

import Foundation

// MARK: - Knoten-Typen

struct RepositoryBookmark: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var path: URL
    // Sicher persistierbar (kein Geheimnis):
    var remoteURL: String?   // HTTPS-Remote für geklonte Repos
    var username: String?    // HTTPS-Benutzername — Passwort/Token NUR im Keychain
    var isPinned: Bool       // Als Favorit oben in der Seitenleiste angepinnt

    init(id: UUID = UUID(), name: String, path: URL, remoteURL: String? = nil, username: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.remoteURL = remoteURL
        self.username = username
        self.isPinned = isPinned
    }

    // Eigenes Dekodieren: ältere bookmarks.json kennt `isPinned` nicht. Das synthetisierte
    // Decodable würde daran scheitern und den gesamten Baum verwerfen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(URL.self, forKey: .path)
        remoteURL = try c.decodeIfPresent(String.self, forKey: .remoteURL)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

struct BookmarkFolder: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var children: [BookmarkNode]

    init(id: UUID = UUID(), name: String, children: [BookmarkNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

// MARK: - Baum-Knoten

indirect enum BookmarkNode: Identifiable, Hashable, Codable {
    case folder(BookmarkFolder)
    case repository(RepositoryBookmark)

    var id: UUID {
        switch self {
        case .folder(let f): f.id
        case .repository(let r): r.id
        }
    }

    var displayName: String {
        switch self {
        case .folder(let f): f.name
        case .repository(let r): r.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var children: [BookmarkNode]? {
        if case .folder(let f) = self { return f.children }
        return nil
    }
}

// MARK: - Hilfsmethoden für Baum-Mutationen

extension [BookmarkNode] {
    /// Gibt alle Repository-Lesezeichen im Baum rekursiv zurück (flache Liste, Tiefensuche).
    func allRepositories() -> [RepositoryBookmark] {
        var result: [RepositoryBookmark] = []
        for node in self {
            if case .repository(let repo) = node {
                result.append(repo)
            }
            if case .folder(let folder) = node {
                result.append(contentsOf: folder.children.allRepositories())
            }
        }
        return result
    }

    /// Alle angepinnten Repositories, alphabetisch nach Name sortiert.
    func pinnedRepositories() -> [RepositoryBookmark] {
        allRepositories()
            .filter(\.isPinned)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Setzt den Favoriten-Status des Repositories mit der gegebenen ID.
    mutating func setPinned(id: UUID, _ pinned: Bool) {
        for i in indices {
            if case .repository(var repo) = self[i], repo.id == id {
                repo.isPinned = pinned
                self[i] = .repository(repo)
                return
            }
            if case .folder(var folder) = self[i] {
                folder.children.setPinned(id: id, pinned)
                self[i] = .folder(folder)
            }
        }
    }

    /// Gibt alle Ordner im Baum rekursiv zurück (flache Liste, Tiefensuche).
    func allFolders() -> [BookmarkFolder] {
        var result: [BookmarkFolder] = []
        for node in self {
            if case .folder(let folder) = node {
                result.append(folder)
                result.append(contentsOf: folder.children.allFolders())
            }
        }
        return result
    }

    /// Sucht rekursiv ein Repository-Lesezeichen mit der gegebenen ID.
    func findRepository(id: UUID) -> RepositoryBookmark? {
        for node in self {
            if case .repository(let repo) = node, repo.id == id {
                return repo
            }
            if case .folder(let folder) = node {
                if let found = folder.children.findRepository(id: id) {
                    return found
                }
            }
        }
        return nil
    }


    /// Entfernt den Knoten mit der gegebenen ID rekursiv aus dem Baum.
    /// Gibt zurück, ob etwas entfernt wurde.
    @discardableResult
    mutating func remove(id: UUID) -> BookmarkNode? {
        for i in indices {
            if self[i].id == id {
                return remove(at: i)
            }
            if case .folder(var folder) = self[i] {
                if let removed = folder.children.remove(id: id) {
                    self[i] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }

    /// Benennt den Knoten mit der gegebenen ID um.
    mutating func rename(id: UUID, to newName: String) {
        for i in indices {
            if self[i].id == id {
                switch self[i] {
                case .folder(var f):
                    f.name = newName
                    self[i] = .folder(f)
                case .repository(var r):
                    r.name = newName
                    self[i] = .repository(r)
                }
                return
            }
            if case .folder(var folder) = self[i] {
                folder.children.rename(id: id, to: newName)
                self[i] = .folder(folder)
            }
        }
    }

    /// Verschiebt einen Knoten in einen Ziel-Ordner (oder auf Root-Ebene wenn targetFolderID nil).
    /// Entfernt zuerst den Knoten, fügt ihn dann am Ziel ein.
    mutating func move(id: UUID, toFolder targetFolderID: UUID?) {
        guard let node = remove(id: id) else { return }
        if let targetFolderID {
            insert(node, intoFolderWithID: targetFolderID)
        } else {
            self.append(node)
        }
    }

    /// Aktualisiert den Pfad eines Repository-Lesezeichens mit der gegebenen ID.
    mutating func updateRepositoryPath(id: UUID, newPath: URL) {
        for i in indices {
            if case .repository(var repo) = self[i], repo.id == id {
                repo.path = newPath
                self[i] = .repository(repo)
                return
            }
            if case .folder(var folder) = self[i] {
                folder.children.updateRepositoryPath(id: id, newPath: newPath)
                self[i] = .folder(folder)
            }
        }
    }

    private mutating func insert(_ node: BookmarkNode, intoFolderWithID folderID: UUID) {
        for i in indices {
            if case .folder(var folder) = self[i] {
                if folder.id == folderID {
                    folder.children.append(node)
                    self[i] = .folder(folder)
                    return
                }
                folder.children.insert(node, intoFolderWithID: folderID)
                self[i] = .folder(folder)
            }
        }
    }
}
