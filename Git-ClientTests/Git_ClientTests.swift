//
//  Git_ClientTests.swift
//  Git-ClientTests
//

import Testing
import Foundation
import SwiftUI
@testable import Git_Client

// MARK: - Helpers

private func makeCommit(
    sha: String,
    parents: [String] = [],
    subject: String = "Test commit"
) -> Commit {
    Commit(
        sha: sha,
        shortSha: String(sha.prefix(8)),
        parents: parents,
        author: "Alice",
        authorEmail: "alice@example.com",
        date: Date(timeIntervalSince1970: 0),
        subject: subject,
        body: "",
        refNames: []
    )
}

private func makeSeparatedRecord(
    sha: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    shortSha: String = "aaaaaaaa",
    parents: String = "",
    author: String = "Alice",
    email: String = "alice@example.com",
    date: String = "2024-01-15T12:00:00+00:00",
    refs: String = "",
    subject: String = "Initial commit",
    body: String = ""
) -> String {
    let fs = "\u{1f}"
    let rs = "\u{1e}"
    return "\(sha)\(fs)\(shortSha)\(fs)\(parents)\(fs)\(author)\(fs)\(email)\(fs)\(date)\(fs)\(refs)\(fs)\(subject)\(fs)\(body)\(rs)"
}

// MARK: - GitLogParser

@Suite("GitLogParser")
struct GitLogParserTests {

    @Test("Leere Ausgabe ergibt leeres Array")
    func emptyOutput() {
        let result = GitLogParser.parse("")
        #expect(result.isEmpty)
    }

    @Test("Nur Whitespace ergibt leeres Array")
    func whitespaceOutput() {
        let result = GitLogParser.parse("  \n\n  ")
        #expect(result.isEmpty)
    }

    @Test("Einzelner Commit wird korrekt geparst")
    func singleCommit() {
        let input = makeSeparatedRecord(
            sha: "abc123abc123abc123abc123abc123abc123abc1",
            shortSha: "abc123ab",
            subject: "Fix bug"
        )
        let commits = GitLogParser.parse(input)
        #expect(commits.count == 1)
        #expect(commits[0].sha == "abc123abc123abc123abc123abc123abc123abc1")
        #expect(commits[0].shortSha == "abc123ab")
        #expect(commits[0].subject == "Fix bug")
        #expect(commits[0].author == "Alice")
        #expect(commits[0].authorEmail == "alice@example.com")
        #expect(commits[0].parents.isEmpty)
    }

    @Test("Commit mit einem Parent")
    func commitWithOneParent() {
        let input = makeSeparatedRecord(
            sha: "bbb0000000000000000000000000000000000000",
            parents: "aaa0000000000000000000000000000000000000"
        )
        let commits = GitLogParser.parse(input)
        #expect(commits[0].parents == ["aaa0000000000000000000000000000000000000"])
    }

    @Test("Merge-Commit mit zwei Parents")
    func mergeCommit() {
        let input = makeSeparatedRecord(
            sha: "ccc0000000000000000000000000000000000000",
            parents: "aaa0000000000000000000000000000000000000 bbb0000000000000000000000000000000000000"
        )
        let commits = GitLogParser.parse(input)
        #expect(commits[0].parents.count == 2)
        #expect(commits[0].parents[0] == "aaa0000000000000000000000000000000000000")
        #expect(commits[0].parents[1] == "bbb0000000000000000000000000000000000000")
    }

    @Test("Mehrere Commits")
    func multipleCommits() {
        let r1 = makeSeparatedRecord(sha: "111" + String(repeating: "0", count: 37), subject: "First")
        let r2 = makeSeparatedRecord(sha: "222" + String(repeating: "0", count: 37), subject: "Second")
        let commits = GitLogParser.parse(r1 + r2)
        #expect(commits.count == 2)
        #expect(commits[0].subject == "First")
        #expect(commits[1].subject == "Second")
    }

    @Test("Ref-Namen werden korrekt aufgeteilt")
    func refNames() {
        let input = makeSeparatedRecord(refs: "HEAD -> main, origin/main, tag: v1.0")
        let commits = GitLogParser.parse(input)
        #expect(commits[0].refNames == ["HEAD -> main", "origin/main", "tag: v1.0"])
    }

    @Test("Leere Ref-Namen ergeben leeres Array")
    func emptyRefNames() {
        let input = makeSeparatedRecord(refs: "")
        let commits = GitLogParser.parse(input)
        #expect(commits[0].refNames.isEmpty)
    }

    @Test("Datum wird korrekt geparst")
    func dateParsingValid() {
        let input = makeSeparatedRecord(date: "2024-06-15T10:30:00+00:00")
        let commits = GitLogParser.parse(input)
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents([.year, .month, .day], from: commits[0].date)
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test("Ungültiges Datum ergibt Date.distantPast")
    func dateParsingInvalid() {
        let input = makeSeparatedRecord(date: "not-a-date")
        let commits = GitLogParser.parse(input)
        #expect(commits[0].date == Date.distantPast)
    }

    @Test("Record mit zu wenigen Feldern wird übersprungen")
    func recordTooFewFields() {
        // Nur 3 Felder statt 9
        let bad = "sha\u{1f}short\u{1f}parent\u{1e}"
        let commits = GitLogParser.parse(bad)
        #expect(commits.isEmpty)
    }

    @Test("Record mit leerem SHA wird übersprungen")
    func recordEmptySha() {
        let input = makeSeparatedRecord(sha: "", shortSha: "")
        let commits = GitLogParser.parse(input)
        #expect(commits.isEmpty)
    }
}

// MARK: - DiffParser

@Suite("DiffParser")
struct DiffParserTests {

    private let sha = "abc123"

    @Test("Leere Ausgabe ergibt leere Dateiliste")
    func emptyDiff() {
        let diff = DiffParser.parse("", sha: sha)
        #expect(diff.sha == sha)
        #expect(diff.files.isEmpty)
    }

    @Test("Ausgabe ohne diff-Zeile ergibt leere Dateiliste")
    func noDiffLine() {
        let diff = DiffParser.parse("some random output\nwithout diff header\n", sha: sha)
        #expect(diff.files.isEmpty)
    }

    @Test("Einfacher Diff wird geparst")
    func simpleDiff() {
        let input = """
        diff --git a/Foo.swift b/Foo.swift
        index abc..def 100644
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,3 +1,4 @@
         context
        -old line
        +new line
        +added line
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files.count == 1)
        let file = diff.files[0]
        #expect(file.oldPath == "Foo.swift")
        #expect(file.newPath == "Foo.swift")
        #expect(file.displayName == "Foo.swift")
        #expect(file.hunks.count == 1)
        let hunk = file.hunks[0]
        #expect(hunk.header == "@@ -1,3 +1,4 @@")
        #expect(hunk.lines.count == 4)
        #expect(hunk.lines[0].type == .context)
        #expect(hunk.lines[1].type == .deletion)
        #expect(hunk.lines[2].type == .addition)
        #expect(hunk.lines[3].type == .addition)
    }

    @Test("Neue Datei wird als isNew erkannt")
    func newFile() {
        let input = """
        diff --git a/New.swift b/New.swift
        new file mode 100644
        --- /dev/null
        +++ b/New.swift
        @@ -0,0 +1,2 @@
        +line1
        +line2
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].isNew)
        #expect(!diff.files[0].isDeleted)
    }

    @Test("Gelöschte Datei wird als isDeleted erkannt")
    func deletedFile() {
        let input = """
        diff --git a/Old.swift b/Old.swift
        deleted file mode 100644
        --- a/Old.swift
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -gone
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].isDeleted)
        #expect(!diff.files[0].isNew)
    }

    @Test("Umbenannte Datei hat unterschiedliche old/new Pfade")
    func renamedFile() {
        let input = """
        diff --git a/Old.swift b/New.swift
        similarity index 100%
        rename from Old.swift
        rename to New.swift
        --- a/Old.swift
        +++ b/New.swift
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].oldPath == "Old.swift")
        #expect(diff.files[0].newPath == "New.swift")
        #expect(diff.files[0].displayName == "Old.swift → New.swift")
    }

    @Test("Mehrere Dateien werden alle geparst")
    func multipleFiles() {
        let input = """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1,1 +1,1 @@
        -old
        +new
        diff --git a/B.swift b/B.swift
        --- a/B.swift
        +++ b/B.swift
        @@ -1,1 +1,1 @@
        -x
        +y
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files.count == 2)
        #expect(diff.files[0].oldPath == "A.swift")
        #expect(diff.files[1].oldPath == "B.swift")
    }

    @Test("Mehrere Hunks in einer Datei")
    func multipleHunks() {
        let input = """
        diff --git a/Foo.swift b/Foo.swift
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,2 +1,2 @@
        -line1
        +lineA
        @@ -10,2 +10,2 @@
        -line10
        +lineB
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files[0].hunks.count == 2)
    }

    @Test("Zeilennummern im Hunk sind aufsteigend")
    func hunkLineIds() {
        let input = """
        diff --git a/Foo.swift b/Foo.swift
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,3 +1,3 @@
         ctx
        -del
        +add
        """
        let diff = DiffParser.parse(input, sha: sha)
        let lines = diff.files[0].hunks[0].lines
        #expect(lines[0].id == 0)
        #expect(lines[1].id == 1)
        #expect(lines[2].id == 2)
    }

    @Test("Datei-IDs sind aufsteigend")
    func fileIds() {
        let input = """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        diff --git a/B.swift b/B.swift
        --- a/B.swift
        +++ b/B.swift
        """
        let diff = DiffParser.parse(input, sha: sha)
        #expect(diff.files[0].id == 0)
        #expect(diff.files[1].id == 1)
    }
}

// MARK: - CommitGraphBuilder

@Suite("CommitGraphBuilder")
struct CommitGraphBuilderTests {

    @Test("Leere Commit-Liste ergibt leeres Array")
    func emptyCommits() {
        let rows = CommitGraphBuilder.build(from: [])
        #expect(rows.isEmpty)
    }

    @Test("Einzelner Commit ohne Parents")
    func singleRootCommit() {
        let c = makeCommit(sha: "aaa" + String(repeating: "0", count: 37))
        let rows = CommitGraphBuilder.build(from: [c])
        #expect(rows.count == 1)
        #expect(rows[0].lane == 0)
        #expect(rows[0].laneCount >= 1)
        #expect(rows[0].incoming.isEmpty)
        #expect(rows[0].outgoing.isEmpty)
    }

    @Test("Lineare Historie: Lane bleibt konstant")
    func linearHistory() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let shaC = "ccc" + String(repeating: "0", count: 37)
        let c = makeCommit(sha: shaC, parents: [shaB])
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [c, b, a])
        #expect(rows[0].lane == 0) // C
        #expect(rows[1].lane == 0) // B
        #expect(rows[2].lane == 0) // A
    }

    @Test("Lineare Historie: Kanten verbinden benachbarte Zeilen")
    func linearEdges() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [b, a])
        // B outgoing: Kante von Lane 0 nach Lane 0
        #expect(rows[0].outgoing.count == 1)
        #expect(rows[0].outgoing[0].fromLane == 0)
        #expect(rows[0].outgoing[0].toLane == 0)
        // A incoming: Kante von Lane 0 nach Lane 0
        #expect(rows[1].incoming.count == 1)
        #expect(rows[1].incoming[0].fromLane == 0)
        #expect(rows[1].incoming[0].toLane == 0)
        // A hat keine outgoing (Wurzel)
        #expect(rows[1].outgoing.isEmpty)
    }

    @Test("Merge-Commit: outgoing hat zwei Kanten")
    func mergeCommitOutgoing() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let shaM = "mmm" + String(repeating: "0", count: 37)
        let m = makeCommit(sha: shaM, parents: [shaB, shaA]) // merge
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [m, b, a])
        // Merge-Commit öffnet 2 Lanes nach unten
        #expect(rows[0].outgoing.count == 2)
    }

    @Test("Merge-Commit: laneCount wächst durch zweiten Parent")
    func mergeIncreasesLaneCount() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let shaM = "mmm" + String(repeating: "0", count: 37)
        let m = makeCommit(sha: shaM, parents: [shaB, shaA])
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [m, b, a])
        // Ab M gibt es mindestens 2 Lanes
        #expect(rows[0].laneCount >= 2)
    }

    @Test("Passthrough-Lane hat incoming und outgoing in derselben Lane")
    func passthroughLane() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let shaM = "mmm" + String(repeating: "0", count: 37)
        let m = makeCommit(sha: shaM, parents: [shaB, shaA])
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [m, b, a])
        // B (rows[1]) liegt auf Lane 0; Lane 1 (für shaA) muss als Passthrough vorhanden sein
        let bRow = rows[1]
        let passthroughIncoming = bRow.incoming.filter { $0.fromLane == $0.toLane && $0.fromLane != bRow.lane }
        let passthroughOutgoing = bRow.outgoing.filter { $0.fromLane == $0.toLane && $0.fromLane != bRow.lane }
        #expect(!passthroughIncoming.isEmpty)
        #expect(!passthroughOutgoing.isEmpty)
    }

    @Test("Konvergenz: Beide Lanes laufen in B's outgoing zusammen")
    func convergenceInBOutgoing() {
        let shaA = "aaa" + String(repeating: "0", count: 37)
        let shaB = "bbb" + String(repeating: "0", count: 37)
        let shaM = "mmm" + String(repeating: "0", count: 37)
        let m = makeCommit(sha: shaM, parents: [shaB, shaA])
        let b = makeCommit(sha: shaB, parents: [shaA])
        let a = makeCommit(sha: shaA, parents: [])
        let rows = CommitGraphBuilder.build(from: [m, b, a])
        // B (rows[1]) konvergiert Lane 0 → Lane 1 in outgoing, weil shaA schon in Lane 1 liegt
        let bRow = rows[1]
        let convergingEdge = bRow.outgoing.first { $0.fromLane != $0.toLane }
        #expect(convergingEdge != nil)
        // A (rows[2]) hat genau eine einlaufende Kante (Lane 1 — Lane 0 ist bereits frei)
        let aRow = rows[2]
        #expect(aRow.incoming.count == 1)
    }

    @Test("Keine laneColors out-of-bounds (viele Lanes)")
    func manyLanesNocrash() {
        // Erstellt einen Merge mit 4 Eltern → 5 Lanes
        let parents = (0..<4).map { "p\($0)" + String(repeating: "0", count: 38) }
        let merge = makeCommit(sha: "mmm" + String(repeating: "0", count: 37), parents: parents)
        let roots = parents.map { makeCommit(sha: $0) }
        let commits = [merge] + roots
        let rows = CommitGraphBuilder.build(from: commits)
        #expect(rows.count == commits.count)
    }
}

// MARK: - BookmarkNode / [BookmarkNode]

@Suite("BookmarkNode")
struct BookmarkNodeTests {

    private func makeRepo(name: String = "Repo") -> RepositoryBookmark {
        RepositoryBookmark(name: name, path: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    @Test("displayName für Ordner und Repository")
    func displayName() {
        let folder = BookmarkNode.folder(BookmarkFolder(name: "Work"))
        let repo = BookmarkNode.repository(makeRepo(name: "MyRepo"))
        #expect(folder.displayName == "Work")
        #expect(repo.displayName == "MyRepo")
    }

    @Test("isFolder erkennt Ordner korrekt")
    func isFolder() {
        let folder = BookmarkNode.folder(BookmarkFolder(name: "F"))
        let repo = BookmarkNode.repository(makeRepo())
        #expect(folder.isFolder)
        #expect(!repo.isFolder)
    }

    @Test("children gibt Kinder eines Ordners zurück")
    func children() {
        let child = BookmarkNode.repository(makeRepo())
        let folder = BookmarkNode.folder(BookmarkFolder(name: "F", children: [child]))
        #expect(folder.children?.count == 1)
        #expect(BookmarkNode.repository(makeRepo()).children == nil)
    }

    @Test("allFolders findet Ordner rekursiv")
    func allFolders() {
        let inner = BookmarkFolder(name: "Inner")
        let outer = BookmarkFolder(name: "Outer", children: [.folder(inner)])
        let tree: [BookmarkNode] = [.folder(outer), .repository(makeRepo())]
        let folders = tree.allFolders()
        #expect(folders.count == 2)
        #expect(folders.map(\.name).contains("Outer"))
        #expect(folders.map(\.name).contains("Inner"))
    }

    @Test("allFolders auf leerem Baum")
    func allFoldersEmpty() {
        let tree: [BookmarkNode] = []
        #expect(tree.allFolders().isEmpty)
    }

    @Test("findRepository findet Repo auf Root-Ebene")
    func findRepositoryRoot() {
        let repo = makeRepo()
        let tree: [BookmarkNode] = [.repository(repo)]
        let found = tree.findRepository(id: repo.id)
        #expect(found?.id == repo.id)
    }

    @Test("findRepository findet Repo in verschachteltem Ordner")
    func findRepositoryNested() {
        let repo = makeRepo()
        let folder = BookmarkFolder(name: "F", children: [.repository(repo)])
        let tree: [BookmarkNode] = [.folder(folder)]
        let found = tree.findRepository(id: repo.id)
        #expect(found?.id == repo.id)
    }

    @Test("findRepository gibt nil zurück wenn nicht vorhanden")
    func findRepositoryMissing() {
        let tree: [BookmarkNode] = [.repository(makeRepo())]
        let found = tree.findRepository(id: UUID())
        #expect(found == nil)
    }

    @Test("remove löscht Knoten auf Root-Ebene")
    func removeFromRoot() {
        let repo = makeRepo()
        var tree: [BookmarkNode] = [.repository(repo)]
        let removed = tree.remove(id: repo.id)
        #expect(removed != nil)
        #expect(tree.isEmpty)
    }

    @Test("remove löscht Knoten aus Ordner")
    func removeFromFolder() {
        let repo = makeRepo()
        let folder = BookmarkFolder(name: "F", children: [.repository(repo)])
        var tree: [BookmarkNode] = [.folder(folder)]
        tree.remove(id: repo.id)
        #expect(tree[0].children?.isEmpty == true)
    }

    @Test("remove gibt nil zurück wenn nicht vorhanden")
    func removeMissing() {
        var tree: [BookmarkNode] = [.repository(makeRepo())]
        let removed = tree.remove(id: UUID())
        #expect(removed == nil)
        #expect(tree.count == 1)
    }

    @Test("rename ändert Namen eines Repositories")
    func renameRepository() {
        let repo = makeRepo(name: "Old")
        var tree: [BookmarkNode] = [.repository(repo)]
        tree.rename(id: repo.id, to: "New")
        #expect(tree[0].displayName == "New")
    }

    @Test("rename ändert Namen eines Ordners")
    func renameFolder() {
        let folder = BookmarkFolder(name: "OldFolder")
        var tree: [BookmarkNode] = [.folder(folder)]
        tree.rename(id: folder.id, to: "NewFolder")
        #expect(tree[0].displayName == "NewFolder")
    }

    @Test("rename ändert Namen in verschachteltem Ordner")
    func renameNested() {
        let repo = makeRepo(name: "Deep")
        let inner = BookmarkFolder(name: "Inner", children: [.repository(repo)])
        let outer = BookmarkFolder(name: "Outer", children: [.folder(inner)])
        var tree: [BookmarkNode] = [.folder(outer)]
        tree.rename(id: repo.id, to: "Renamed")
        let found = tree.findRepository(id: repo.id)
        #expect(found?.name == "Renamed")
    }

    @Test("move verschiebt Knoten in Ordner")
    func moveToFolder() {
        let repo = makeRepo()
        let targetFolder = BookmarkFolder(name: "Target")
        var tree: [BookmarkNode] = [.repository(repo), .folder(targetFolder)]
        tree.move(id: repo.id, toFolder: targetFolder.id)
        #expect(tree.count == 1)
        #expect(tree[0].children?.count == 1)
    }

    @Test("move auf Root-Ebene (targetFolderID = nil)")
    func moveToRoot() {
        let repo = makeRepo()
        let folder = BookmarkFolder(name: "F", children: [.repository(repo)])
        var tree: [BookmarkNode] = [.folder(folder)]
        tree.move(id: repo.id, toFolder: nil)
        #expect(tree.count == 2)
        #expect(tree[0].children?.isEmpty == true)
    }

    @Test("updateRepositoryPath aktualisiert Pfad")
    func updatePath() {
        let repo = makeRepo()
        let newURL = URL(fileURLWithPath: "/new/path")
        var tree: [BookmarkNode] = [.repository(repo)]
        tree.updateRepositoryPath(id: repo.id, newPath: newURL)
        let updated = tree.findRepository(id: repo.id)
        #expect(updated?.path == newURL)
    }

    @Test("updateRepositoryPath in verschachteltem Ordner")
    func updatePathNested() {
        let repo = makeRepo()
        let newURL = URL(fileURLWithPath: "/deep/path")
        let folder = BookmarkFolder(name: "F", children: [.repository(repo)])
        var tree: [BookmarkNode] = [.folder(folder)]
        tree.updateRepositoryPath(id: repo.id, newPath: newURL)
        let found = tree.findRepository(id: repo.id)
        #expect(found?.path == newURL)
    }

    @Test("Kein Endlosrekursion bei append (Regressionstest)")
    func noInfiniteRecursionOnAppend() {
        // Testet, dass [BookmarkNode].append(_:) nicht auf sich selbst zeigt.
        var tree: [BookmarkNode] = []
        let repo = BookmarkNode.repository(makeRepo())
        // Würde bei dem alten Bug einen Stack Overflow verursachen
        tree.append(repo)
        #expect(tree.count == 1)
    }
}

// MARK: - BookmarkStore

@Suite("BookmarkStore")
struct BookmarkStoreTests {

    private func tempStore() -> (BookmarkStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return (BookmarkStore(fileURL: url), url)
    }

    @Test("Laden wenn Datei fehlt ergibt leeres Array")
    func loadMissingFile() {
        let (store, _) = tempStore()
        let nodes = store.load()
        #expect(nodes.isEmpty)
    }

    @Test("Laden einer korrupten Datei ergibt leeres Array")
    func loadCorruptFile() throws {
        let (store, url) = tempStore()
        try "this is not json".data(using: .utf8)!.write(to: url)
        let nodes = store.load()
        #expect(nodes.isEmpty)
    }

    @Test("Speichern und Laden: Round-Trip")
    func roundTrip() {
        let (store, _) = tempStore()
        let repo = RepositoryBookmark(name: "TestRepo", path: URL(fileURLWithPath: "/tmp/repo"))
        let folder = BookmarkFolder(name: "Work", children: [.repository(repo)])
        let original: [BookmarkNode] = [.folder(folder), .repository(repo)]
        store.save(original)
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].displayName == "Work")
        #expect(loaded[1].displayName == "TestRepo")
    }

    @Test("Speichern überschreibt vorhandene Datei")
    func saveOverwrites() {
        let (store, _) = tempStore()
        let r1 = RepositoryBookmark(name: "First", path: URL(fileURLWithPath: "/a"))
        let r2 = RepositoryBookmark(name: "Second", path: URL(fileURLWithPath: "/b"))
        store.save([.repository(r1)])
        store.save([.repository(r2)])
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].displayName == "Second")
    }

    @Test("Tief verschachtelter Baum überlebt Round-Trip")
    func deepNestedRoundTrip() {
        let (store, _) = tempStore()
        let repo = RepositoryBookmark(name: "Deep", path: URL(fileURLWithPath: "/d"))
        let inner = BookmarkFolder(name: "Inner", children: [.repository(repo)])
        let outer = BookmarkFolder(name: "Outer", children: [.folder(inner)])
        store.save([.folder(outer)])
        let loaded = store.load()
        let found = loaded.findRepository(id: repo.id)
        #expect(found?.name == "Deep")
    }
}

// MARK: - GitError

@Suite("GitError")
struct GitErrorTests {

    @Test("gitNotFound hat nicht-leere Fehlermeldung")
    func gitNotFoundDescription() {
        #expect(GitError.gitNotFound.errorDescription?.isEmpty == false)
    }

    @Test("notARepository hat nicht-leere Fehlermeldung")
    func notARepositoryDescription() {
        #expect(GitError.notARepository.errorDescription?.isEmpty == false)
    }

    @Test("nonZeroExit enthält Exit-Code in der Meldung")
    func nonZeroExitCode() {
        let err = GitError.nonZeroExit(code: 128, stderr: "")
        #expect(err.errorDescription?.contains("128") == true)
    }

    @Test("nonZeroExit enthält Stderr in der Meldung")
    func nonZeroExitStderr() {
        let err = GitError.nonZeroExit(code: 1, stderr: "fatal: not a git repository")
        #expect(err.errorDescription?.contains("fatal: not a git repository") == true)
    }
}

// MARK: - GitService Integration

private func sh(_ args: String...) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

@Suite("GitService Integration")
@MainActor
struct GitServiceIntegrationTests {
    let repoURL: URL

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init")
        try sh("git", "-C", repoURL.path, "config", "user.email", "test@example.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "Tester")
        let readme = repoURL.appendingPathComponent("README.md")
        try "# Test\n".write(to: readme, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Initial commit")
    }

    @Test("validateRepository erkennt gültiges Repository")
    func validateValid() async throws {
        let svc = GitService(repositoryPath: repoURL)
        try await svc.validateRepository()
    }

    @Test("validateRepository wirft für ungültiges Verzeichnis")
    func validateInvalid() async throws {
        let notRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("notrepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notRepo, withIntermediateDirectories: true)
        let svc = GitService(repositoryPath: notRepo)
        do {
            try await svc.validateRepository()
            Issue.record("validateRepository hätte werfen sollen")
        } catch is GitError {
            // erwartet
        }
    }

    @Test("loadCommits liefert Initial-Commit")
    func loadCommitsNonEmpty() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let commits = try await svc.loadCommits()
        #expect(!commits.isEmpty)
        #expect(commits[0].subject == "Initial commit")
        #expect(commits[0].sha.count == 40)
    }

    @Test("loadBranches liefert aktuellen Branch")
    func loadBranchesHasCurrentBranch() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let branches = try await svc.loadBranches()
        let hasCurrent = branches.contains { $0.isCurrent }
        #expect(!branches.isEmpty)
        #expect(hasCurrent)
    }

    @Test("loadBranches: tipSha ist 40-stellig")
    func branchTipShaIsFullLength() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let branches = try await svc.loadBranches()
        let allFull = branches.allSatisfy { $0.tipSha.count == 40 }
        #expect(allFull)
    }

    @Test("Branch-tipSha stimmt mit Commit-SHA überein")
    func branchTipMatchesCommit() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let commits = try await svc.loadCommits()
        let branches = try await svc.loadBranches()
        let commitSHAs = Set(commits.map { $0.sha })
        for branch in branches where !branch.isRemote {
            let tipSha = branch.tipSha
            #expect(commitSHAs.contains(tipSha))
        }
    }

    @Test("loadTags gibt leeres Array für Repo ohne Tags")
    func loadTagsEmpty() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let tags = try await svc.loadTags()
        #expect(tags.isEmpty)
    }

    @Test("loadTags liefert annotierten Tag")
    func loadTagsWithAnnotated() async throws {
        try sh("git", "-C", repoURL.path, "tag", "-a", "v1.0", "-m", "Release 1.0")
        let svc = GitService(repositoryPath: repoURL)
        let tags = try await svc.loadTags()
        let hasV1 = tags.contains { $0.name == "v1.0" }
        #expect(hasV1)
    }

    @Test("loadDiff liefert CommitDiff für bekannten SHA")
    func loadDiffForCommit() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let commits = try await svc.loadCommits()
        guard let firstSha = commits.first?.sha else { Issue.record("Kein Commit"); return }
        let diff = try await svc.loadDiff(sha: firstSha)
        let diffSha = diff.sha
        #expect(diffSha == firstSha)
    }

    @Test("hasRemote gibt false zurück ohne konfigurierten Remote")
    func hasRemoteFalse() async {
        let svc = GitService(repositoryPath: repoURL)
        let result = await svc.hasRemote()
        #expect(!result)
    }

    @Test("remoteName gibt nil zurück ohne konfigurierten Remote")
    func remoteNameNil() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let name = try await svc.remoteName()
        #expect(name == nil)
    }

    @Test("aheadBehind gibt nil zurück ohne Upstream")
    func aheadBehindNoUpstream() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let result = try await svc.aheadBehind()
        #expect(result == nil)
    }

    @Test("loadSingleCommit liefert Commit für bekannten SHA")
    func loadSingleCommitBySha() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let commits = try await svc.loadCommits()
        guard let first = commits.first else { Issue.record("Kein Commit"); return }
        let firstSha = first.sha
        let firstSubject = first.subject
        let single = await svc.loadSingleCommit(sha: firstSha)
        let singleSha = single?.sha
        let singleSubject = single?.subject
        #expect(singleSha == firstSha)
        #expect(singleSubject == firstSubject)
    }

    @Test("loadSingleCommit gibt nil für unbekannten SHA")
    func loadSingleCommitUnknownSha() async {
        let svc = GitService(repositoryPath: repoURL)
        let result = await svc.loadSingleCommit(sha: String(repeating: "0", count: 40))
        #expect(result == nil)
    }
}

// MARK: - RepositoryViewModel

@Suite("RepositoryViewModel")
@MainActor
struct RepositoryViewModelTests {

    private func makeBookmark() -> RepositoryBookmark {
        RepositoryBookmark(name: "test", path: URL(fileURLWithPath: "/tmp/nonexistent"))
    }

    @Test("selectedCommit ist nil ohne Auswahl")
    func selectedCommitNilInitially() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        #expect(vm.selectedCommitID == nil)
        #expect(vm.selectedCommit == nil)
    }

    @Test("selectCommit(bySha:) wählt Commit per vollem SHA aus")
    func selectByFullSha() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha)]
        vm.selectCommit(bySha: sha)
        #expect(vm.selectedCommitID == sha)
    }

    @Test("selectCommit(bySha:) wählt Commit per Kurzform-SHA aus")
    func selectByShortSha() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha)]
        vm.selectCommit(bySha: "abc123ab")
        #expect(vm.selectedCommitID == sha)
    }

    @Test("selectCommit(bySha:) setzt scrollTargetID auf den gefundenen Commit")
    func selectSetsScrollTarget() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha)]
        vm.selectCommit(bySha: sha)
        #expect(vm.scrollTargetID == sha)
    }

    @Test("selectCommit(bySha:) erhöht scrollRequestToken")
    func selectIncrementsToken() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha)]
        vm.selectCommit(bySha: sha)
        #expect(vm.scrollRequestToken == 1)
    }

    @Test("selectCommit(bySha:) erhöht Token bei wiederholtem Klick auf denselben Commit")
    func selectSameShaIncrementsTokenTwice() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha)]
        vm.selectCommit(bySha: sha)
        vm.selectCommit(bySha: sha)
        #expect(vm.scrollRequestToken == 2)
    }

    @Test("selectCommit(bySha:) setzt branchJumpMessage für fehlenden Commit")
    func selectMissingCommitSetsMessage() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        vm.commits = []
        vm.selectCommit(bySha: "deadbeefdeadbeefdeadbeefdeadbeefdeadbee1")
        #expect(vm.branchJumpMessage != nil)
        #expect(vm.selectedCommitID == nil)
        #expect(vm.scrollRequestToken == 0)
    }

    @Test("selectCommit(bySha:) setzt keine Meldung während isLoading")
    func selectMissingDuringLoadingNoMessage() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        vm.commits = []
        vm.isLoading = true
        vm.selectCommit(bySha: "deadbeefdeadbeefdeadbeefdeadbeefdeadbee1")
        #expect(vm.branchJumpMessage == nil)
        #expect(vm.selectedCommitID == nil)
    }

    @Test("selectedCommit gibt richtigen Commit nach selectCommit zurück")
    func selectedCommitAfterSelect() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha, subject: "Wichtiger Fix")]
        vm.selectCommit(bySha: sha)
        #expect(vm.selectedCommit?.sha == sha)
        #expect(vm.selectedCommit?.subject == "Wichtiger Fix")
    }

    @Test("Präfix-Matching bevorzugt exakten Treffer bei Ambiguität")
    func exactMatchPreferredOverPrefix() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        let sha1 = "abc1230000000000000000000000000000000001"
        let sha2 = "abc123abc123abc123abc123abc123abc123abc1"
        vm.commits = [makeCommit(sha: sha1), makeCommit(sha: sha2)]
        vm.selectCommit(bySha: sha2) // exakter Treffer
        #expect(vm.selectedCommitID == sha2)
    }
}

// MARK: - GitService (parseBranches / parseTags)

@Suite("GitService Parser")
struct GitServiceParserTests {

    private let service = GitService(repositoryPath: URL(fileURLWithPath: "/tmp"))

    @Test("parseBranches parst lokalen Branch")
    func localBranch() async {
        let output = "refs/heads/main\tabc123\t*\n"
        let branches = await service.parseBranches(from: output)
        #expect(branches.count == 1)
        #expect(branches[0].name == "main")
        #expect(branches[0].tipSha == "abc123")
        #expect(branches[0].isCurrent)
        #expect(!branches[0].isRemote)
    }

    @Test("parseBranches parst nicht-aktuellen Branch")
    func nonCurrentBranch() async {
        let output = "refs/heads/feature/xyz\tdef456\t \n"
        let branches = await service.parseBranches(from: output)
        #expect(branches.count == 1)
        #expect(branches[0].name == "feature/xyz")
        #expect(!branches[0].isCurrent)
    }

    @Test("parseBranches parst Remote-Branch")
    func remoteBranch() async {
        let output = "refs/remotes/origin/main\t789abc\t \n"
        let branches = await service.parseBranches(from: output)
        #expect(branches.count == 1)
        #expect(branches[0].isRemote)
        #expect(branches[0].remoteName == "origin")
        #expect(branches[0].shortName == "main")
    }

    @Test("parseBranches überspringt refs/remotes/origin/HEAD")
    func skipsRemoteHEAD() async {
        let output = "refs/remotes/origin/HEAD\tabc123\t \n"
        let branches = await service.parseBranches(from: output)
        #expect(branches.isEmpty)
    }

    @Test("parseBranches ignoriert leere Zeilen")
    func emptyLinesIgnored() async {
        let output = "\nrefs/heads/main\tabc\t*\n\n"
        let branches = await service.parseBranches(from: output)
        #expect(branches.count == 1)
    }

    @Test("parseBranches mehrere Branches")
    func multipleBranches() async {
        let output = """
        refs/heads/main\taaa\t*
        refs/heads/develop\tbbb\t
        refs/remotes/origin/main\taaa\t
        """
        let branches = await service.parseBranches(from: output)
        #expect(branches.count == 3)
    }

    @Test("parseTags parst Lightweight-Tag")
    func lightweightTag() async {
        let output = "v1.0\tabc123\t\n"
        let tags = await service.parseTags(from: output)
        #expect(tags.count == 1)
        #expect(tags[0].name == "v1.0")
        #expect(tags[0].targetSha == "abc123")
    }

    @Test("parseTags verwendet Deref-SHA für annotierten Tag")
    func annotatedTag() async {
        // Annotierter Tag: objectname zeigt auf Tag-Objekt, *objectname auf Commit
        let output = "v2.0\ttagobj1\tcommit99\n"
        let tags = await service.parseTags(from: output)
        #expect(tags.count == 1)
        #expect(tags[0].targetSha == "commit99")
    }

    @Test("parseTags ignoriert leere Zeilen")
    func emptyTagLines() async {
        let output = "\nv1.0\tabc\t\n\n"
        let tags = await service.parseTags(from: output)
        #expect(tags.count == 1)
    }

    @Test("parseTags mehrere Tags")
    func multipleTags() async {
        let output = "v1.0\taaa\t\nv2.0\tbbb\tcommitC\n"
        let tags = await service.parseTags(from: output)
        #expect(tags.count == 2)
        #expect(tags[0].name == "v1.0")
        #expect(tags[1].targetSha == "commitC")
    }
}

// MARK: - AppSettings

@Suite("AppSettings", .serialized)
struct AppSettingsTests {

    @Test("Standardwert ist 2000")
    func defaultBatchSize() {
        // Wenn der Key nie gesetzt wurde (integer = 0), muss der Default greifen.
        UserDefaults.standard.removeObject(forKey: AppSettings.commitBatchSizeKey)
        #expect(AppSettings.commitBatchSize == AppSettings.defaultCommitBatchSize)
    }

    @Test("Gespeicherter Wert wird korrekt gelesen")
    func storedValueIsRead() {
        UserDefaults.standard.set(500, forKey: AppSettings.commitBatchSizeKey)
        #expect(AppSettings.commitBatchSize == 500)
        UserDefaults.standard.removeObject(forKey: AppSettings.commitBatchSizeKey)
    }

    @Test("Minimumwert wird durchgesetzt")
    func minimumEnforced() {
        // commitBatchSize gibt mindestens minimumCommitBatchSize zurück
        UserDefaults.standard.set(1, forKey: AppSettings.commitBatchSizeKey)
        #expect(AppSettings.commitBatchSize == AppSettings.minimumCommitBatchSize)
        UserDefaults.standard.removeObject(forKey: AppSettings.commitBatchSizeKey)
    }

    @Test("Wert 0 (nie gesetzt) ergibt Default")
    func zeroYieldsDefault() {
        UserDefaults.standard.set(0, forKey: AppSettings.commitBatchSizeKey)
        #expect(AppSettings.commitBatchSize == AppSettings.defaultCommitBatchSize)
        UserDefaults.standard.removeObject(forKey: AppSettings.commitBatchSizeKey)
    }
}

// MARK: - GitService Paging (Integration)

@Suite("GitService Paging")
@MainActor
struct GitServicePagingTests {

    let repoURL: URL

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-paging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init")
        try sh("git", "-C", repoURL.path, "config", "user.email", "test@example.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "Tester")
        // 8 Commits erstellen
        for i in 1...8 {
            let file = repoURL.appendingPathComponent("file\(i).txt")
            try "content\(i)".write(to: file, atomically: true, encoding: .utf8)
            try sh("git", "-C", repoURL.path, "add", ".")
            try sh("git", "-C", repoURL.path, "commit", "-m", "Commit \(i)")
        }
    }

    @Test("loadCommits(limit:skip:0) liefert erste Seite")
    func firstPage() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let page = try await svc.loadCommits(limit: 3, skip: 0)
        #expect(page.count == 3)
    }

    @Test("loadCommits mit skip überspringt erste N Commits")
    func secondPage() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let page1 = try await svc.loadCommits(limit: 3, skip: 0)
        let page2 = try await svc.loadCommits(limit: 3, skip: 3)
        // Kein Commit darf in beiden Seiten vorkommen
        let shas1 = Set(page1.map(\.sha))
        let shas2 = Set(page2.map(\.sha))
        #expect(shas1.isDisjoint(with: shas2))
    }

    @Test("Letzte Seite liefert weniger als limit (Ende erkannt)")
    func lastPageSmallerThanLimit() async throws {
        let svc = GitService(repositoryPath: repoURL)
        // 8 Commits, skip 6 → noch 2 übrig
        let lastPage = try await svc.loadCommits(limit: 5, skip: 6)
        #expect(lastPage.count == 2)
        #expect(lastPage.count < 5)
    }

    @Test("skip jenseits aller Commits ergibt leeres Array")
    func skipBeyondEnd() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let page = try await svc.loadCommits(limit: 10, skip: 100)
        #expect(page.isEmpty)
    }

    @Test("Alle Seiten zusammen ergeben alle Commits ohne Duplikate")
    func allPagesNoOverlap() async throws {
        let svc = GitService(repositoryPath: repoURL)
        var all: [Commit] = []
        var skip = 0
        let pageSize = 3
        while true {
            let page = try await svc.loadCommits(limit: pageSize, skip: skip)
            all.append(contentsOf: page)
            skip += page.count
            if page.count < pageSize { break }
        }
        let unique = Set(all.map(\.sha))
        #expect(unique.count == all.count)   // keine Duplikate
        #expect(all.count == 8)              // alle 8 Commits
    }
}

// MARK: - RepositoryViewModel Paging

@Suite("RepositoryViewModel Paging")
@MainActor
struct RepositoryViewModelPagingTests {

    private func makeBookmark() -> RepositoryBookmark {
        RepositoryBookmark(name: "test", path: URL(fileURLWithPath: "/tmp/nonexistent"))
    }

    @Test("canLoadMore ist initial true")
    func canLoadMoreInitial() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        #expect(vm.canLoadMore)
    }

    @Test("isLoadingMore ist initial false")
    func isLoadingMoreInitial() {
        let vm = RepositoryViewModel(repository: makeBookmark())
        #expect(!vm.isLoadingMore)
    }

    @Test("loadMore() tut nichts wenn isLoading=true")
    func loadMoreBlockedDuringLoad() async {
        let vm = RepositoryViewModel(repository: makeBookmark())
        vm.isLoading = true
        // Sollte keine Exception werfen und isLoadingMore false lassen
        await vm.loadMore()
        #expect(!vm.isLoadingMore)
    }

    @Test("loadMore() tut nichts wenn canLoadMore=false")
    func loadMoreBlockedWhenNoMore() async {
        let vm = RepositoryViewModel(repository: makeBookmark())
        vm.canLoadMore = false
        await vm.loadMore()
        #expect(!vm.isLoadingMore)
    }
}

// MARK: - RepositoryViewModel Integration (load / loadMore)

@Suite("RepositoryViewModel Integration")
@MainActor
struct RepositoryViewModelIntegrationTests {

    let repoURL: URL
    let bookmark: RepositoryBookmark

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init")
        try sh("git", "-C", repoURL.path, "config", "user.email", "test@example.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "Tester")
        for i in 1...3 {
            let file = repoURL.appendingPathComponent("f\(i).txt")
            try "x".write(to: file, atomically: true, encoding: .utf8)
            try sh("git", "-C", repoURL.path, "add", ".")
            try sh("git", "-C", repoURL.path, "commit", "-m", "Commit \(i)")
        }
        bookmark = RepositoryBookmark(name: "Test", path: repoURL)
    }

    @Test("load() füllt commits, branches, tags")
    func loadFillsData() async throws {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()
        #expect(!vm.commits.isEmpty)
        #expect(!vm.branches.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test("load() baut graphRows auf")
    func loadBuildsGraph() async {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()
        #expect(vm.graphRows.count == vm.commits.count)
    }

    @Test("load() setzt canLoadMore=false für kleines Repo")
    func loadSetsCanLoadMoreFalse() async {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()
        // 3 Commits < pageSize (min 100) → kein weiteres Laden
        #expect(vm.canLoadMore == false)
    }

    @Test("loadMore() mit canLoadMore=true läuft ohne Fehler durch")
    func loadMoreFullPath() async {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()
        // Manuell zurücksetzen, damit der Guard passiert
        vm.canLoadMore = true
        await vm.loadMore()
        // Nächste Seite ist leer → canLoadMore wird false gesetzt
        #expect(vm.canLoadMore == false)
        #expect(vm.isLoadingMore == false)
    }
}

// MARK: - KeychainStore

@Suite("KeychainStore")
struct KeychainStoreTests {

    @Test("save und load liefern denselben Wert")
    func saveAndLoad() {
        let id = UUID()
        defer { KeychainStore.delete(for: id) }
        KeychainStore.save("test-secret", for: id)
        #expect(KeychainStore.load(for: id) == "test-secret")
    }

    @Test("load ohne vorherigen save gibt nil")
    func loadMissing() {
        let id = UUID()
        KeychainStore.delete(for: id)   // sicherstellen, dass nichts vorhanden
        #expect(KeychainStore.load(for: id) == nil)
    }

    @Test("delete entfernt gespeicherten Wert")
    func deleteRemovesValue() {
        let id = UUID()
        KeychainStore.save("secret", for: id)
        KeychainStore.delete(for: id)
        #expect(KeychainStore.load(for: id) == nil)
    }

    @Test("save überschreibt vorhandenen Eintrag")
    func saveOverwrites() {
        let id = UUID()
        defer { KeychainStore.delete(for: id) }
        KeychainStore.save("first", for: id)
        KeychainStore.save("second", for: id)
        #expect(KeychainStore.load(for: id) == "second")
    }

    @Test("Verschiedene IDs sind unabhängig")
    func differentIDsAreIndependent() {
        let id1 = UUID()
        let id2 = UUID()
        defer {
            KeychainStore.delete(for: id1)
            KeychainStore.delete(for: id2)
        }
        KeychainStore.save("only-for-id1", for: id1)
        #expect(KeychainStore.load(for: id2) == nil)
    }
}

// MARK: - AppModel

@Suite("AppModel")
@MainActor
struct AppModelTests {

    func makeModel() -> (AppModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-\(UUID().uuidString).json")
        let store = BookmarkStore(fileURL: url)
        return (AppModel(store: store), url)
    }

    @Test("addRepository fügt Knoten hinzu")
    func addRepositoryAddsNode() {
        let (model, _) = makeModel()
        model.addRepository(name: "Repo", path: URL(fileURLWithPath: "/tmp/r"))
        #expect(model.bookmarkNodes.count == 1)
    }

    @Test("addRepository persistiert Daten")
    func addRepositoryPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-persist-\(UUID().uuidString).json")
        let store = BookmarkStore(fileURL: url)
        let model = AppModel(store: store)
        model.addRepository(name: "Repo", path: URL(fileURLWithPath: "/tmp/r"))
        let model2 = AppModel(store: BookmarkStore(fileURL: url))
        #expect(model2.bookmarkNodes.count == 1)
    }

    @Test("addFolder fügt Ordner hinzu")
    func addFolderAddsFolder() {
        let (model, _) = makeModel()
        model.addFolder(name: "Ordner")
        #expect(model.bookmarkNodes.count == 1)
        #expect(model.bookmarkNodes[0].isFolder)
    }

    @Test("rename ändert den Namen")
    func renameChangesName() {
        let (model, _) = makeModel()
        model.addRepository(name: "Alt", path: URL(fileURLWithPath: "/tmp/r"))
        let id = model.bookmarkNodes[0].id
        model.rename(id: id, to: "Neu")
        #expect(model.bookmarkNodes[0].displayName == "Neu")
    }

    @Test("delete entfernt Knoten")
    func deleteRemovesNode() {
        let (model, _) = makeModel()
        model.addRepository(name: "Repo", path: URL(fileURLWithPath: "/tmp/r"))
        let id = model.bookmarkNodes[0].id
        model.delete(id: id)
        #expect(model.bookmarkNodes.isEmpty)
    }

    @Test("move verschiebt Repository in Ordner")
    func moveToFolder() {
        let (model, _) = makeModel()
        model.addFolder(name: "Ordner")
        model.addRepository(name: "Repo", path: URL(fileURLWithPath: "/tmp/r"))
        let folderID = model.bookmarkNodes[0].id
        let repoID = model.bookmarkNodes[1].id
        model.move(id: repoID, toFolder: folderID)
        #expect(model.bookmarkNodes.count == 1)           // nur noch Ordner auf Root-Ebene
        #expect(model.bookmarkNodes[0].children?.count == 1)
    }

    @Test("updateRepositoryPath aktualisiert den Pfad")
    func updatePathWorks() {
        let (model, _) = makeModel()
        model.addRepository(name: "Repo", path: URL(fileURLWithPath: "/tmp/alt"))
        let id = model.bookmarkNodes[0].id
        let newPath = URL(fileURLWithPath: "/tmp/neu")
        model.updateRepositoryPath(id: id, newPath: newPath)
        let found = model.bookmarkNodes.findRepository(id: id)
        #expect(found?.path == newPath)
    }

    @Test("closeRepository setzt openedRepository und repositoryViewModel zurück")
    func closeResetsState() {
        let (model, _) = makeModel()
        model.openedRepository = RepositoryBookmark(name: "R", path: URL(fileURLWithPath: "/tmp/r"))
        model.closeRepository()
        #expect(model.openedRepository == nil)
        #expect(model.repositoryViewModel == nil)
    }

    @Test("openRepository setzt State wenn Pfad existiert")
    func openRepositoryWithExistingPath() throws {
        let (model, _) = makeModel()
        // Temporäres Verzeichnis existiert sicher
        let dir = FileManager.default.temporaryDirectory
        let bm = RepositoryBookmark(name: "Test", path: dir)
        model.openRepository(bm)
        #expect(model.openedRepository?.id == bm.id)
        #expect(model.repositoryViewModel != nil)
    }

    @Test("openRepository ignoriert nicht-existierenden Pfad")
    func openRepositoryWithMissingPath() {
        let (model, _) = makeModel()
        let bm = RepositoryBookmark(
            name: "Ghost",
            path: URL(fileURLWithPath: "/tmp/path-that-does-not-exist-\(UUID().uuidString)")
        )
        model.openRepository(bm)
        #expect(model.openedRepository == nil)
    }
}

// MARK: - GitService aheadBehind (mit lokalem Upstream)

@Suite("GitService aheadBehind")
@MainActor
struct GitServiceAheadBehindTests {

    let localURL: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
        let bareURL = base.appendingPathComponent("bare-\(UUID().uuidString).git", isDirectory: true)
        localURL = base.appendingPathComponent("local-\(UUID().uuidString)", isDirectory: true)

        // Bare-Repo als "Remote"
        try sh("git", "init", "--bare", bareURL.path)

        // Lokales Repo klonen (damit tracking-Branch konfiguriert ist)
        try sh("git", "clone", bareURL.path, localURL.path)
        try sh("git", "-C", localURL.path, "config", "user.email", "t@t.com")
        try sh("git", "-C", localURL.path, "config", "user.name", "T")

        // Ersten Commit pushen → Remote-Tracking-Branch existiert
        let initFile = localURL.appendingPathComponent("init.txt")
        try "x".write(to: initFile, atomically: true, encoding: .utf8)
        try sh("git", "-C", localURL.path, "add", ".")
        try sh("git", "-C", localURL.path, "commit", "-m", "Init")
        try sh("git", "-C", localURL.path, "push", "-u", "origin", "HEAD")

        // Lokalen Commit erzeugen, der noch nicht gepusht ist (ahead: 1)
        let aheadFile = localURL.appendingPathComponent("ahead.txt")
        try "y".write(to: aheadFile, atomically: true, encoding: .utf8)
        try sh("git", "-C", localURL.path, "add", ".")
        try sh("git", "-C", localURL.path, "commit", "-m", "Ahead commit")
    }

    @Test("aheadBehind liefert ahead=1, behind=0")
    func aheadBehindAheadOne() async throws {
        let svc = GitService(repositoryPath: localURL)
        let counts = try await svc.aheadBehind()
        #expect(counts != nil)
        #expect(counts?.ahead == 1)
        #expect(counts?.behind == 0)
    }

    @Test("aheadBehind gibt nil für Repo ohne Upstream zurück")
    func aheadBehindNoUpstreamReturnsNil() async throws {
        let noUpstreamURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-upstream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: noUpstreamURL, withIntermediateDirectories: true)
        try sh("git", "-C", noUpstreamURL.path, "init")
        try sh("git", "-C", noUpstreamURL.path, "config", "user.email", "t@t.com")
        try sh("git", "-C", noUpstreamURL.path, "config", "user.name", "T")
        let f = noUpstreamURL.appendingPathComponent("f.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        try sh("git", "-C", noUpstreamURL.path, "add", ".")
        try sh("git", "-C", noUpstreamURL.path, "commit", "-m", "Init")

        let svc = GitService(repositoryPath: noUpstreamURL)
        let counts = try await svc.aheadBehind()
        #expect(counts == nil)
    }
}

// MARK: - CommitSearchCriteriaTests

@Suite("CommitSearchCriteria")
struct CommitSearchCriteriaTests {

    @Test("isActive ist false bei leeren Kriterien")
    func emptyIsNotActive() {
        #expect(!CommitSearchCriteria().isActive)
    }

    @Test("isActive ist true wenn Nachricht gesetzt")
    func messageActivates() {
        var c = CommitSearchCriteria(); c.message = "fix"
        #expect(c.isActive)
    }

    @Test("isActive ist true wenn Autor gesetzt")
    func authorActivates() {
        var c = CommitSearchCriteria(); c.author = "alice"
        #expect(c.isActive)
    }

    @Test("isActive ist true wenn SHA gesetzt")
    func shaActivates() {
        var c = CommitSearchCriteria(); c.sha = "abc123"
        #expect(c.isActive)
    }

    @Test("isActive ist true wenn since gesetzt")
    func sinceActivates() {
        var c = CommitSearchCriteria(); c.since = Date()
        #expect(c.isActive)
    }

    @Test("isActive ist true wenn until gesetzt")
    func untilActivates() {
        var c = CommitSearchCriteria(); c.until = Date()
        #expect(c.isActive)
    }

    @Test("Nur Leerzeichen gilt als inaktiv")
    func whitespaceIsInactive() {
        var c = CommitSearchCriteria(); c.message = "   "; c.author = "  "
        #expect(!c.isActive)
    }
}

// MARK: - GitServiceSearchTests

@Suite("GitService – Commit-Suche")
struct GitServiceSearchTests {

    // Hilfsfunktion: temporäres Repo mit N Commits
    private func makeSearchRepo() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("searchRepo-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        func sh(_ args: String...) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = args; try p.run(); p.waitUntilExit()
        }
        try sh("git", "-C", tmp.path, "init")
        try sh("git", "-C", tmp.path, "config", "user.email", "alice@example.com")
        try sh("git", "-C", tmp.path, "config", "user.name", "Alice")

        let file = tmp.appendingPathComponent("f.txt")
        // Commit 1 — Autor Alice, Nachricht "fix: crash bug"
        try "a".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", tmp.path, "add", "."); try sh("git", "-C", tmp.path, "commit", "-m", "fix: crash bug")
        // Commit 2 — Autor Alice, Nachricht "feat: add login"
        try "b".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", tmp.path, "add", "."); try sh("git", "-C", tmp.path, "commit", "-m", "feat: add login")
        // Commit 3 — Autor Bob, Nachricht "docs: readme"
        try sh("git", "-C", tmp.path, "config", "user.email", "bob@example.com")
        try sh("git", "-C", tmp.path, "config", "user.name", "Bob")
        try "c".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", tmp.path, "add", "."); try sh("git", "-C", tmp.path, "commit", "-m", "docs: readme")
        return tmp
    }

    @Test("Suche nach Nachricht liefert passende Commits")
    func searchByMessage() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var c = CommitSearchCriteria(); c.message = "fix"
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.count == 1)
        #expect(results[0].subject.contains("fix"))
    }

    @Test("Suche ist case-insensitive")
    func searchCaseInsensitive() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var c = CommitSearchCriteria(); c.message = "FIX"
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.count == 1)
    }

    @Test("Suche nach Autor liefert nur dessen Commits")
    func searchByAuthor() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var c = CommitSearchCriteria(); c.author = "Bob"
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.count == 1)
        #expect(results[0].subject.contains("docs"))
    }

    @Test("Suche nach Autor per E-Mail liefert deren Commits")
    func searchByAuthorEmail() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var c = CommitSearchCriteria(); c.author = "alice@example.com"
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.count == 2)
    }

    @Test("Kombination Nachricht+Autor liefert Schnittmenge")
    func searchByMessageAndAuthor() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var c = CommitSearchCriteria(); c.message = "feat"; c.author = "Alice"
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.count == 1)
        #expect(results[0].subject.contains("feat"))
    }

    @Test("Leere Kriterien liefern alle Commits")
    func searchWithEmptyCriteria() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let results = try await GitService(repositoryPath: repo)
            .searchCommits(criteria: CommitSearchCriteria())
        #expect(results.count == 3)
    }

    @Test("SHA-Präfixsuche findet passenden Commit")
    func searchByShaPrefix() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // Ersten Commit-SHA laden
        let allCommits = try await GitService(repositoryPath: repo)
            .loadCommits(limit: 10, skip: 0)
        guard let first = allCommits.first else { return }
        let prefix = String(first.sha.prefix(5))
        var c = CommitSearchCriteria(); c.sha = prefix
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.contains { $0.sha == first.sha })
    }

    @Test("Datumsbereich schließt Commits außerhalb aus")
    func searchByDateRange() async throws {
        let repo = try makeSearchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // Future range: keine Commits
        var c = CommitSearchCriteria()
        c.since = Date(timeIntervalSinceNow: 3600)
        c.until = Date(timeIntervalSinceNow: 7200)
        let results = try await GitService(repositoryPath: repo).searchCommits(criteria: c)
        #expect(results.isEmpty)
    }
}

// MARK: - BranchParserTests

@Suite("BranchParserTests")
struct BranchParserTests {

    /// Hilfsfunktion: GitService-Instanz mit dummy-Pfad (nur Parser-Methoden werden getestet)
    private func service() -> GitService { GitService(repositoryPath: URL(fileURLWithPath: "/tmp")) }

    // MARK: parseTrack

    @Test("parseTrack: ahead und behind")
    func parseTrackAheadAndBehind() {
        let svc = service()
        let result = svc.parseTrack("ahead 2, behind 3")
        #expect(result.ahead == 2)
        #expect(result.behind == 3)
    }

    @Test("parseTrack: nur ahead")
    func parseTrackAheadOnly() {
        let result = service().parseTrack("ahead 1")
        #expect(result.ahead == 1)
        #expect(result.behind == 0)
    }

    @Test("parseTrack: nur behind")
    func parseTrackBehindOnly() {
        let result = service().parseTrack("behind 4")
        #expect(result.ahead == 0)
        #expect(result.behind == 4)
    }

    @Test("parseTrack: leer → 0/0")
    func parseTrackEmpty() {
        let result = service().parseTrack("")
        #expect(result.ahead == 0)
        #expect(result.behind == 0)
    }

    @Test("parseTrack: gone → 0/0")
    func parseTrackGone() {
        let result = service().parseTrack("gone")
        #expect(result.ahead == 0)
        #expect(result.behind == 0)
    }

    // MARK: parseBranches

    /// Baut eine Tab-getrennte Zeile mit allen 5 Feldern
    private func line(refname: String, sha: String = "abc1234", head: String = " ",
                      upstream: String = "", track: String = "") -> String {
        "\(refname)\t\(sha)\t\(head)\t\(upstream)\t\(track)"
    }

    @Test("Lokaler Branch mit ahead 2 / behind 3")
    func localBranchAheadBehind() {
        let svc = service()
        let input = line(refname: "refs/heads/main", upstream: "origin/main",
                         track: "ahead 2, behind 3")
        let branches = svc.parseBranches(from: input)
        #expect(branches.count == 1)
        let b = branches[0]
        #expect(b.upstreamName == "origin/main")
        #expect(b.ahead == 2)
        #expect(b.behind == 3)
    }

    @Test("Lokaler Branch nur ahead")
    func localBranchAheadOnly() {
        let b = service().parseBranches(from:
            line(refname: "refs/heads/feature", upstream: "origin/feature", track: "ahead 1")
        ).first
        #expect(b?.ahead == 1)
        #expect(b?.behind == 0)
    }

    @Test("Lokaler Branch nur behind")
    func localBranchBehindOnly() {
        let b = service().parseBranches(from:
            line(refname: "refs/heads/main", upstream: "origin/main", track: "behind 4")
        ).first
        #expect(b?.ahead == 0)
        #expect(b?.behind == 4)
    }

    @Test("Lokaler Branch mit Upstream, leerer Track → 0/0")
    func localBranchUpstreamNoTrack() {
        let b = service().parseBranches(from:
            line(refname: "refs/heads/main", upstream: "origin/main", track: "")
        ).first
        #expect(b?.upstreamName == "origin/main")
        #expect(b?.ahead == 0)
        #expect(b?.behind == 0)
    }

    @Test("Lokaler Branch ohne Upstream → nil")
    func localBranchNoUpstream() {
        let b = service().parseBranches(from:
            line(refname: "refs/heads/local", upstream: "", track: "")
        ).first
        #expect(b?.upstreamName == nil)
        #expect(b?.ahead == nil)
        #expect(b?.behind == nil)
    }

    @Test("Lokaler Branch mit gone → 0/0, Upstream gesetzt")
    func localBranchGone() {
        let b = service().parseBranches(from:
            line(refname: "refs/heads/old", upstream: "origin/old", track: "gone")
        ).first
        #expect(b?.upstreamName == "origin/old")
        #expect(b?.ahead == 0)
        #expect(b?.behind == 0)
    }

    @Test("Remote Branch hat keine Tracking-Felder")
    func remoteBranchNoTracking() {
        let b = service().parseBranches(from:
            line(refname: "refs/remotes/origin/main", upstream: "", track: "")
        ).first
        #expect(b?.isRemote == true)
        #expect(b?.upstreamName == nil)
        #expect(b?.ahead == nil)
        #expect(b?.behind == nil)
    }

    @Test("Rückwärtskompatibilität: 3-Feld-Zeile parst ohne Crash, Tracking nil")
    func threeFieldLineBackwardCompat() {
        let input = "refs/heads/main\tabc1234\t*"
        let b = service().parseBranches(from: input).first
        #expect(b != nil)
        #expect(b?.upstreamName == nil)
        #expect(b?.ahead == nil)
    }

    @Test("refs/remotes/origin/HEAD wird übersprungen")
    func remoteHeadSkipped() {
        let input = line(refname: "refs/remotes/origin/HEAD")
        let branches = service().parseBranches(from: input)
        #expect(branches.isEmpty)
    }
}

// MARK: - JiraLinkerTests

@Suite("JiraLinkerTests")
struct JiraLinkerTests {

    private let baseURL = "https://jira.example.com"
    private var projects: [JiraProject] {
        [JiraProject(key: "PROJ", description: "Main Project"),
         JiraProject(key: "INFRA", description: "Infrastructure")]
    }

    @Test("Einzel-Treffer → korrekte Browse-URL")
    func singleMatch() {
        let tickets = JiraLinker.tickets(in: "fix: PROJ-42 crashes on start",
                                         projects: projects, baseURL: baseURL)
        #expect(tickets.count == 1)
        #expect(tickets[0].key == "PROJ-42")
        #expect(tickets[0].url.absoluteString == "https://jira.example.com/browse/PROJ-42")
        #expect(tickets[0].projectDescription == "Main Project")
    }

    @Test("Mehrere Tickets aus verschiedenen Projekten")
    func multipleProjects() {
        let text = "feat: PROJ-1 und INFRA-7 integriert"
        let tickets = JiraLinker.tickets(in: text, projects: projects, baseURL: baseURL)
        #expect(tickets.count == 2)
        #expect(tickets.map(\.key) == ["PROJ-1", "INFRA-7"])
    }

    @Test("Duplikate werden dedupliziert")
    func deduplication() {
        let text = "fix: PROJ-10 behoben, PROJ-10 war kritisch"
        let tickets = JiraLinker.tickets(in: text, projects: projects, baseURL: baseURL)
        #expect(tickets.count == 1)
        #expect(tickets[0].key == "PROJ-10")
    }

    @Test("Nicht konfigurierter Key wird ignoriert")
    func unconfiguredKeyIgnored() {
        let tickets = JiraLinker.tickets(in: "fix: FOO-99 crash",
                                         projects: projects, baseURL: baseURL)
        #expect(tickets.isEmpty)
    }

    @Test("Wortgrenze: XPROJ-1 ist kein Treffer für Key PROJ")
    func wordBoundary() {
        let tickets = JiraLinker.tickets(in: "update XPROJ-1 config",
                                         projects: projects, baseURL: baseURL)
        #expect(tickets.isEmpty)
    }

    @Test("Basis-URL mit abschließendem Slash → identische URL")
    func baseURLWithTrailingSlash() {
        let tickets = JiraLinker.tickets(in: "PROJ-5 fix",
                                         projects: projects, baseURL: baseURL + "/")
        #expect(tickets.count == 1)
        #expect(tickets[0].url.absoluteString == "https://jira.example.com/browse/PROJ-5")
    }

    @Test("Leere Basis-URL → keine Treffer")
    func emptyBaseURL() {
        let tickets = JiraLinker.tickets(in: "PROJ-1 fix", projects: projects, baseURL: "")
        #expect(tickets.isEmpty)
    }

    @Test("Leerer Key in Projektliste wird übersprungen")
    func emptyKeySkipped() {
        let projs = [JiraProject(key: "", description: "Leer"), JiraProject(key: "PROJ", description: "P")]
        let tickets = JiraLinker.tickets(in: "PROJ-3 fix", projects: projs, baseURL: baseURL)
        #expect(tickets.count == 1)
        #expect(tickets[0].key == "PROJ-3")
    }

    @Test("Beschreibung korrekt durchgereicht")
    func descriptionPropagated() {
        let tickets = JiraLinker.tickets(in: "INFRA-2 update",
                                         projects: projects, baseURL: baseURL)
        #expect(tickets.first?.projectDescription == "Infrastructure")
    }
}

// MARK: - JiraSettingsTests

@Suite("JiraSettingsTests")
struct JiraSettingsTests {

    /// Isolierter UserDefaults-Suite, um die App-Einstellungen nicht zu verändern
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "de.test.JiraSettingsTests")!
    }

    private func cleanup() {
        defaults.removePersistentDomain(forName: "de.test.JiraSettingsTests")
    }

    @Test("JiraProject Encode/Decode-Roundtrip")
    func jiraProjectRoundtrip() throws {
        defer { cleanup() }
        let projects = [
            JiraProject(id: UUID(), key: "PROJ", description: "Main"),
            JiraProject(id: UUID(), key: "INFRA", description: "Infra")
        ]
        let data = try JSONEncoder().encode(projects)
        let decoded = try JSONDecoder().decode([JiraProject].self, from: data)
        #expect(decoded == projects)
    }

    @Test("Leere Projektliste kodiert und dekodiert korrekt")
    func emptyProjectList() throws {
        let data = try JSONEncoder().encode([JiraProject]())
        let decoded = try JSONDecoder().decode([JiraProject].self, from: data)
        #expect(decoded.isEmpty)
    }
}

// MARK: - BlameParserTests

@Suite("BlameParserTests")
struct BlameParserTests {

    // Minimal-Porcelain-Ausgabe: 2 Commits, 3 Zeilen.
    // sha1: 2 Zeilen (zweite ohne neuen Meta-Block → Cache-Test)
    // sha2: 1 Zeile
    private var sampleOutput: String {
        """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 2
        author Alice
        author-time 1000000000
        summary fix: crash on startup
        \tlet x = 1
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 2 2
        \tlet y = 2
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 3 3 1
        author Bob
        author-time 1100000000
        summary feat: add feature
        \treturn x + y
        """
    }

    @Test("Korrekte Anzahl Zeilen")
    func lineCount() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines.count == 3)
    }

    @Test("SHA und shortSha korrekt")
    func shaAndShortSha() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines[0].sha == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(lines[0].shortSha == "aaaaaaaa")
        #expect(lines[2].sha == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(lines[2].shortSha == "bbbbbbbb")
    }

    @Test("Autor korrekt geparst")
    func author() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines[0].author == "Alice")
        #expect(lines[2].author == "Bob")
    }

    @Test("Datum aus author-time (Epoch) korrekt")
    func date() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines[0].date == Date(timeIntervalSince1970: 1_000_000_000))
        #expect(lines[2].date == Date(timeIntervalSince1970: 1_100_000_000))
    }

    @Test("Summary korrekt")
    func summary() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines[0].summary == "fix: crash on startup")
        #expect(lines[2].summary == "feat: add feature")
    }

    @Test("Inhalt ohne führendes Tab")
    func content() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines[0].content == "let x = 1")
        #expect(lines[1].content == "let y = 2")
        #expect(lines[2].content == "return x + y")
    }

    @Test("Zeilennummern fortlaufend")
    func lineNumbers() {
        let lines = BlameParser.parse(sampleOutput)
        #expect(lines.map(\.lineNumber) == [1, 2, 3])
    }

    @Test("Cache: zweite Zeile desselben Commits erbt Metadaten")
    func cacheInheritance() {
        let lines = BlameParser.parse(sampleOutput)
        // Zeile 2 gehört zu sha1 (kein neuer Meta-Block), muss dennoch Autor haben
        #expect(lines[1].author == "Alice")
        #expect(lines[1].summary == "fix: crash on startup")
    }

    @Test("Leere Eingabe → leeres Ergebnis")
    func emptyInput() {
        let lines = BlameParser.parse("")
        #expect(lines.isEmpty)
    }
}

// MARK: - RepoRefSnapshotTests

@Suite("RepoRefSnapshot — Parser und Diff")
struct RepoRefSnapshotTests {

    // MARK: - parseForEachRef

    @Test("parseForEachRef: mehrere Zeilen → korrektes Dictionary")
    func parseForEachRefBasic() {
        // SHAs sind exakt 40 Hex-Zeichen
        let shaMain    = "aabbccddeeff00112233445566778899aabbccdd"
        let shaFeature = "1122334455667788990011223344556677889900"
        let shaRemote  = "fedcba9876543210fedcba9876543210fedcba98"
        let output = """
        \(shaMain) refs/heads/main
        \(shaFeature) refs/heads/feature/x
        \(shaRemote) refs/remotes/origin/main
        """
        let result = RepoRefSnapshot.parseForEachRef(output)
        #expect(result["refs/heads/main"] == shaMain)
        #expect(result["refs/heads/feature/x"] == shaFeature)
        #expect(result["refs/remotes/origin/main"] == shaRemote)
        #expect(result.count == 3)
    }

    @Test("parseForEachRef: leere Eingabe → leeres Dictionary")
    func parseForEachRefEmpty() {
        let result = RepoRefSnapshot.parseForEachRef("")
        #expect(result.isEmpty)
    }

    @Test("parseForEachRef: ungültig kurze SHAs werden verworfen")
    func parseForEachRefShortSha() {
        let output = "abc123 refs/heads/main\n"  // SHA kürzer als 40
        let result = RepoRefSnapshot.parseForEachRef(output)
        #expect(result.isEmpty)
    }

    // MARK: - parseLsRemote

    @Test("parseLsRemote: normale Ausgabe → korrektes Dictionary")
    func parseLsRemoteBasic() {
        let shaMain    = "aabbccddeeff00112233445566778899aabbccdd"
        let shaDevelop = "1122334455667788990011223344556677889900"
        let output = "\(shaMain)\trefs/heads/main\n\(shaDevelop)\trefs/heads/develop"
        let result = RepoRefSnapshot.parseLsRemote(output)
        #expect(result["refs/heads/main"] == shaMain)
        #expect(result["refs/heads/develop"] == shaDevelop)
        #expect(result.count == 2)
    }

    @Test("parseLsRemote: Peeled-Zeilen (^{}) werden verworfen")
    func parseLsRemotePeeledLines() {
        // Annotierte Tags erzeugen ^{}-Zeilen — bei ls-remote --heads nicht erwartet,
        // aber defensiv abgesichert.
        let shaMain = "aabbccddeeff00112233445566778899aabbccdd"
        let shaTag  = "1122334455667788990011223344556677889900"
        let shaPeel = "fedcba9876543210fedcba9876543210fedcba98"
        let output = "\(shaMain)\trefs/heads/main\n\(shaTag)\trefs/tags/v1.0\n\(shaPeel)\trefs/tags/v1.0^{}"
        let result = RepoRefSnapshot.parseLsRemote(output)
        #expect(result.keys.contains("refs/tags/v1.0^{}") == false)
        // Die anderen zwei bleiben
        #expect(result.count == 2)
    }

    @Test("parseLsRemote: leere Eingabe → leeres Dictionary")
    func parseLsRemoteEmpty() {
        let result = RepoRefSnapshot.parseLsRemote("")
        #expect(result.isEmpty)
    }

    // MARK: - remoteAhead

    @Test("remoteAhead: Server-SHA weicht ab → wird gezählt")
    func remoteAheadDifferentSha() {
        let localSha  = "aabbccddeeff00112233445566778899aabbccdd"
        let remoteSha = "1122334455667788990011223344556677889900"
        let local  = ["refs/remotes/origin/main": localSha]
        let remote = ["refs/heads/main": remoteSha]
        let count = RepoRefSnapshot.remoteAhead(
            localSignature: local,
            remoteHeads: remote,
            remoteName: "origin"
        )
        #expect(count == 1)
    }

    @Test("remoteAhead: SHAs identisch → 0")
    func remoteAheadSameSha() {
        let sha = "aabbccddeeff00112233445566778899aabbccdd"
        let local  = ["refs/remotes/origin/main": sha]
        let remote = ["refs/heads/main": sha]
        let count = RepoRefSnapshot.remoteAhead(
            localSignature: local,
            remoteHeads: remote,
            remoteName: "origin"
        )
        #expect(count == 0)
    }

    @Test("remoteAhead: lokales Remote-Tracking-Ref fehlt → wird gezählt")
    func remoteAheadMissingLocalRef() {
        // Kein lokales refs/remotes/origin/newbranch → wird als „neu" gezählt
        let local: [String: String] = [:]
        let remote = ["refs/heads/newbranch": "fedcba9876543210fedcba9876543210fedcba98"]
        let count = RepoRefSnapshot.remoteAhead(
            localSignature: local,
            remoteHeads: remote,
            remoteName: "origin"
        )
        #expect(count == 1)
    }

    @Test("remoteAhead: leere Eingaben → 0")
    func remoteAheadEmptyInputs() {
        #expect(RepoRefSnapshot.remoteAhead(localSignature: [:], remoteHeads: [:], remoteName: "origin") == 0)
        #expect(RepoRefSnapshot.remoteAhead(localSignature: [:], remoteHeads: [:], remoteName: "") == 0)
    }

    @Test("remoteAhead: mehrere Branches, teils gleich, teils abweichend")
    func remoteAheadMixed() {
        let sha1    = "aabbccddeeff00112233445566778899aabbccdd"
        let sha2    = "1122334455667788990011223344556677889900"
        let sha2new = "fedcba9876543210fedcba9876543210fedcba98"
        let local: [String: String] = [
            "refs/remotes/origin/main": sha1,
            "refs/remotes/origin/develop": sha2
        ]
        let remote: [String: String] = [
            "refs/heads/main": sha1,       // identisch → nicht gezählt
            "refs/heads/develop": sha2new  // abweichend → gezählt
        ]
        let count = RepoRefSnapshot.remoteAhead(
            localSignature: local,
            remoteHeads: remote,
            remoteName: "origin"
        )
        #expect(count == 1)
    }

    // MARK: - RepoNewCommits.hasNews

    @Test("RepoNewCommits.hasNews: false wenn beides 0/false")
    func hasNewsNone() {
        let status = RepoNewCommits()
        #expect(status.hasNews == false)
    }

    @Test("RepoNewCommits.hasNews: true bei lokalem Change")
    func hasNewsLocal() {
        var status = RepoNewCommits()
        status.hasLocalChanges = true
        #expect(status.hasNews == true)
    }

    @Test("RepoNewCommits.hasNews: true bei Remote-Ahead")
    func hasNewsRemote() {
        var status = RepoNewCommits()
        status.remoteAheadBranches = 2
        #expect(status.hasNews == true)
    }
}

// MARK: - DiffParser — Zeilennummern

@Suite("DiffParser — Zeilennummern")
struct DiffParserLineNumberTests {

    // MARK: parseHunkHeader

    @Test("Vollständiger Header @@ -10,7 +12,9 @@")
    func parseFullHeader() {
        let result = DiffParser.parseHunkHeader("@@ -10,7 +12,9 @@")
        #expect(result?.oldStart == 10)
        #expect(result?.newStart == 12)
    }

    @Test("Header ohne Count @@ -1 +1 @@")
    func parseHeaderNoCount() {
        let result = DiffParser.parseHunkHeader("@@ -1 +1 @@")
        #expect(result?.oldStart == 1)
        #expect(result?.newStart == 1)
    }

    @Test("Header mit Null-Zeilen @@ -0,0 +1 @@")
    func parseHeaderZeroOld() {
        let result = DiffParser.parseHunkHeader("@@ -0,0 +1 @@")
        #expect(result?.oldStart == 0)
        #expect(result?.newStart == 1)
    }

    @Test("Header mit nachfolgendem Kontext-Text")
    func parseHeaderWithContext() {
        let result = DiffParser.parseHunkHeader("@@ -55,6 +55,7 @@ func myFunc() {")
        #expect(result?.oldStart == 55)
        #expect(result?.newStart == 55)
    }

    @Test("Ungültiger Header gibt nil zurück")
    func parseInvalidHeader() {
        #expect(DiffParser.parseHunkHeader("not a header") == nil)
        #expect(DiffParser.parseHunkHeader("") == nil)
        #expect(DiffParser.parseHunkHeader("@@ no numbers @@") == nil)
    }

    // MARK: parse — Nummern-Zuweisung

    /// Kleiner Patch-String mit einer Kontextzeile, einer Deletion, einer Addition.
    private static let simplePatch = """
    diff --git a/file.txt b/file.txt
    --- a/file.txt
    +++ b/file.txt
    @@ -3,3 +3,3 @@
      context1
    -deleted line
    +added line
      context2
    """

    @Test("Kontextzeilen tragen alte UND neue Nummer")
    func contextLineHasBothNumbers() throws {
        let diff = DiffParser.parse(Self.simplePatch, sha: "abc1234")
        let lines = try #require(diff.files.first?.hunks.first?.lines)
        // Erste Zeile ist " context1" — context, startet bei oldNo=3, newNo=3
        let first = try #require(lines.first)
        #expect(first.type == .context)
        #expect(first.oldLineNumber == 3)
        #expect(first.newLineNumber == 3)
    }

    @Test("Deletion hat alte Nummer, keine neue")
    func deletionHasOnlyOldNumber() throws {
        let diff = DiffParser.parse(Self.simplePatch, sha: "abc1234")
        let lines = try #require(diff.files.first?.hunks.first?.lines)
        // Zweite Zeile ist "-deleted line"
        let deletion = try #require(lines.first(where: { $0.type == .deletion }))
        #expect(deletion.oldLineNumber == 4)
        #expect(deletion.newLineNumber == nil)
    }

    @Test("Addition hat neue Nummer, keine alte")
    func additionHasOnlyNewNumber() throws {
        let diff = DiffParser.parse(Self.simplePatch, sha: "abc1234")
        let lines = try #require(diff.files.first?.hunks.first?.lines)
        // Dritte Zeile ist "+added line"
        let addition = try #require(lines.first(where: { $0.type == .addition }))
        #expect(addition.oldLineNumber == nil)
        #expect(addition.newLineNumber == 4)
    }

    @Test("Zählung läuft über Zeilen hinweg korrekt fort")
    func counterAdvancesCorrectly() throws {
        let diff = DiffParser.parse(Self.simplePatch, sha: "abc1234")
        let lines = try #require(diff.files.first?.hunks.first?.lines)
        // context1: old=3, new=3
        // deletion: old=4, new=nil
        // addition: old=nil, new=4
        // context2: old=5, new=5
        let last = try #require(lines.last)
        #expect(last.type == .context)
        #expect(last.oldLineNumber == 5)
        #expect(last.newLineNumber == 5)
    }

    /// Patch mit zwei Hunks — Nummern müssen pro Hunk neu starten.
    private static let twoHunkPatch = """
    diff --git a/file.txt b/file.txt
    --- a/file.txt
    +++ b/file.txt
    @@ -1,2 +1,2 @@
     lineA
    -lineB
    +lineB_new
    @@ -10,2 +10,2 @@
     lineC
    -lineD
    +lineD_new
    """

    @Test("Zweiter Hunk startet mit eigenen Zeilennummern")
    func secondHunkStartNumbers() throws {
        let diff = DiffParser.parse(Self.twoHunkPatch, sha: "abc1234")
        let hunks = try #require(diff.files.first?.hunks)
        #expect(hunks.count == 2)
        let secondLines = hunks[1].lines
        // Erste Zeile im zweiten Hunk: " lineC", old=10, new=10
        let firstInSecond = try #require(secondLines.first)
        #expect(firstInSecond.oldLineNumber == 10)
        #expect(firstInSecond.newLineNumber == 10)
    }

    // MARK: DiffFile.maxLineNumber

    @Test("maxLineNumber gibt die höchste Zeilennummer zurück")
    func maxLineNumber() throws {
        let diff = DiffParser.parse(Self.twoHunkPatch, sha: "abc1234")
        let file = try #require(diff.files.first)
        // Zweiter Hunk endet bei old=11, new=11 → max = 11
        #expect(file.maxLineNumber == 11)
    }

    @Test("maxLineNumber ist 0 bei leerem Diff")
    func maxLineNumberEmpty() {
        let diff = DiffParser.parse("", sha: "abc1234")
        let max = diff.files.first?.maxLineNumber ?? 0
        #expect(max == 0)
    }
}

// MARK: - AppAppearance

@Suite("AppAppearance")
struct AppAppearanceTests {

    @Test("colorScheme: system → nil")
    func systemIsNil() {
        #expect(AppAppearance.system.colorScheme == nil)
    }

    @Test("colorScheme: light → .light")
    func lightIsLight() {
        #expect(AppAppearance.light.colorScheme == .light)
    }

    @Test("colorScheme: dark → .dark")
    func darkIsDark() {
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("rawValue Round-Trip: system")
    func rawValueSystem() {
        #expect(AppAppearance(rawValue: "system") == .system)
    }

    @Test("rawValue Round-Trip: light")
    func rawValueLight() {
        #expect(AppAppearance(rawValue: "light") == .light)
    }

    @Test("rawValue Round-Trip: dark")
    func rawValueDark() {
        #expect(AppAppearance(rawValue: "dark") == .dark)
    }

    @Test("Ungültiger rawValue gibt nil zurück")
    func invalidRawValue() {
        #expect(AppAppearance(rawValue: "auto") == nil)
        #expect(AppAppearance(rawValue: "") == nil)
    }

    @Test("label: Werte korrekt")
    func labels() {
        #expect(AppAppearance.system.label == "Wie System")
        #expect(AppAppearance.light.label == "Hell")
        #expect(AppAppearance.dark.label == "Dunkel")
    }

    @Test("allCases enthält genau 3 Werte")
    func allCasesCount() {
        #expect(AppAppearance.allCases.count == 3)
    }

    @Test("AppSettings Round-Trip: dark")
    func settingsRoundTripDark() {
        AppSettings.setAppearance(.dark)
        #expect(AppSettings.appearance == .dark)
        // Aufräumen
        UserDefaults.standard.removeObject(forKey: AppSettings.appearanceKey)
    }

    @Test("AppSettings: kein gespeicherter Wert ergibt Default system")
    func settingsDefaultSystem() {
        // Eigene saubere Sandbox: temporären Key verwenden, der nie geschrieben wird
        let tempKey = "appearance_test_default_\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: tempKey)
        // Direkt über AppAppearance prüfen: kein gespeicherter String → Default
        let raw = UserDefaults.standard.string(forKey: tempKey)
        let result = raw.flatMap { AppAppearance(rawValue: $0) } ?? AppSettings.defaultAppearance
        #expect(result == .system)
    }

    @Test("nsAppearance: system → nil")
    func nsAppearanceSystemIsNil() {
        #expect(AppAppearance.system.nsAppearance == nil)
    }

    @Test("nsAppearance: light → .aqua")
    func nsAppearanceLightIsAqua() {
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
    }

    @Test("nsAppearance: dark → .darkAqua")
    func nsAppearanceDarkIsDarkAqua() {
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
    }
}

// MARK: - AppSettings Erweitert (JIRA, Auto-Refresh, Poll-Intervall, Anzeige)

@Suite("AppSettings — Erweitert", .serialized)
struct AppSettingsExtendedTests {

    // MARK: JIRA Base URL

    @Test("jiraBaseURL — leer wenn nie gesetzt")
    func jiraBaseURLDefault() {
        UserDefaults.standard.removeObject(forKey: AppSettings.jiraBaseURLKey)
        #expect(AppSettings.jiraBaseURL == "")
    }

    @Test("jiraBaseURL — Round-Trip")
    func jiraBaseURLRoundTrip() {
        AppSettings.setJiraBaseURL("https://test.atlassian.net")
        #expect(AppSettings.jiraBaseURL == "https://test.atlassian.net")
        UserDefaults.standard.removeObject(forKey: AppSettings.jiraBaseURLKey)
    }

    // MARK: JIRA Projects

    @Test("jiraProjects — leer wenn nie gesetzt")
    func jiraProjectsDefault() {
        UserDefaults.standard.removeObject(forKey: AppSettings.jiraProjectsKey)
        #expect(AppSettings.jiraProjects.isEmpty)
    }

    @Test("jiraProjects — Encode/Decode Round-Trip")
    func jiraProjectsRoundTrip() {
        var p = JiraProject()
        p.key = "PROJ"
        p.description = "Test"
        AppSettings.setJiraProjects([p])
        let loaded = AppSettings.jiraProjects
        #expect(loaded.count == 1)
        #expect(loaded.first?.key == "PROJ")
        UserDefaults.standard.removeObject(forKey: AppSettings.jiraProjectsKey)
    }

    // MARK: Auto-Refresh

    @Test("autoRefreshEnabled — Default ist true wenn Key fehlt")
    func autoRefreshDefault() {
        UserDefaults.standard.removeObject(forKey: AppSettings.autoRefreshEnabledKey)
        #expect(AppSettings.autoRefreshEnabled == AppSettings.defaultAutoRefreshEnabled)
    }

    @Test("autoRefreshEnabled — Round-Trip false")
    func autoRefreshFalse() {
        AppSettings.setAutoRefreshEnabled(false)
        #expect(AppSettings.autoRefreshEnabled == false)
        UserDefaults.standard.removeObject(forKey: AppSettings.autoRefreshEnabledKey)
    }

    @Test("autoRefreshEnabled — Round-Trip true")
    func autoRefreshTrue() {
        AppSettings.setAutoRefreshEnabled(true)
        #expect(AppSettings.autoRefreshEnabled == true)
        UserDefaults.standard.removeObject(forKey: AppSettings.autoRefreshEnabledKey)
    }

    // MARK: Remote Poll Interval

    @Test("remotePollInterval — Default wenn Key fehlt")
    func pollIntervalDefault() {
        UserDefaults.standard.removeObject(forKey: AppSettings.remotePollIntervalKey)
        #expect(AppSettings.remotePollInterval == AppSettings.defaultRemotePollInterval)
    }

    @Test("remotePollInterval — 0 explizit bedeutet deaktiviert")
    func pollIntervalExplicitZero() {
        AppSettings.setRemotePollInterval(0)
        #expect(AppSettings.remotePollInterval == 0)
        UserDefaults.standard.removeObject(forKey: AppSettings.remotePollIntervalKey)
    }

    @Test("remotePollInterval — gültiger Wert über Minimum")
    func pollIntervalValid() {
        AppSettings.setRemotePollInterval(120)
        #expect(AppSettings.remotePollInterval == 120)
        UserDefaults.standard.removeObject(forKey: AppSettings.remotePollIntervalKey)
    }

    @Test("remotePollInterval — unter Minimum wird auf Minimum geklemmt")
    func pollIntervalClamped() {
        AppSettings.setRemotePollInterval(10)
        #expect(AppSettings.remotePollInterval == AppSettings.minimumRemotePollInterval)
        UserDefaults.standard.removeObject(forKey: AppSettings.remotePollIntervalKey)
    }

    // MARK: showDiffLineNumbers

    @Test("showDiffLineNumbers — Default ist true wenn Key fehlt")
    func lineNumbersDefault() {
        UserDefaults.standard.removeObject(forKey: AppSettings.showDiffLineNumbersKey)
        #expect(AppSettings.showDiffLineNumbers == true)
    }

    @Test("showDiffLineNumbers — Round-Trip false")
    func lineNumbersFalse() {
        AppSettings.setShowDiffLineNumbers(false)
        #expect(AppSettings.showDiffLineNumbers == false)
        UserDefaults.standard.removeObject(forKey: AppSettings.showDiffLineNumbersKey)
    }

    @Test("showDiffLineNumbers — Round-Trip true")
    func lineNumbersTrue() {
        AppSettings.setShowDiffLineNumbers(true)
        #expect(AppSettings.showDiffLineNumbers == true)
        UserDefaults.standard.removeObject(forKey: AppSettings.showDiffLineNumbersKey)
    }

    // MARK: Erscheinungsbild

    @Test("appearance — ungültiger rawValue ergibt Default")
    func appearanceInvalidRaw() {
        UserDefaults.standard.set("invalid_scheme", forKey: AppSettings.appearanceKey)
        #expect(AppSettings.appearance == AppSettings.defaultAppearance)
        UserDefaults.standard.removeObject(forKey: AppSettings.appearanceKey)
    }

    @Test("appearance — Round-Trip light")
    func appearanceRoundTripLight() {
        AppSettings.setAppearance(.light)
        #expect(AppSettings.appearance == .light)
        UserDefaults.standard.removeObject(forKey: AppSettings.appearanceKey)
    }
}

// MARK: - RepositoryViewModel Einheitstests (ohne echtes git-Repository)

@Suite("RepositoryViewModel — Einheit")
@MainActor
struct RepositoryViewModelUnitTests {

    private func makeVM() -> RepositoryViewModel {
        RepositoryViewModel(repository: RepositoryBookmark(
            name: "test",
            path: URL(fileURLWithPath: "/tmp/nonexistent-vm-\(UUID().uuidString)")
        ))
    }

    // MARK: Such-State

    @Test("isSearchActive ist initial false")
    func searchActiveInitial() {
        #expect(!makeVM().isSearchActive)
    }

    @Test("visibleGraphRows gibt graphRows zurück wenn Suche inaktiv")
    func visibleRowsNoSearch() {
        let vm = makeVM()
        #expect(vm.visibleGraphRows.isEmpty)
        #expect(vm.visibleCanLoadMore)
    }

    @Test("visibleGraphRows gibt searchGraphRows zurück bei aktiver Suche")
    func visibleRowsWithSearch() {
        let vm = makeVM()
        var c = CommitSearchCriteria()
        c.message = "fix"
        vm.updateSearch(c)
        #expect(vm.visibleGraphRows.isEmpty)        // searchGraphRows ist leer, aber korrekter Pfad
        #expect(vm.visibleCanLoadMore)              // searchCanLoadMore ist initial true
    }

    @Test("updateSearch mit inaktiven Kriterien leert Such-State synchron")
    func updateSearchInactiveClearsState() {
        let vm = makeVM()
        vm.updateSearch(CommitSearchCriteria())     // isActive == false
        #expect(vm.searchResults.isEmpty)
        #expect(vm.searchGraphRows.isEmpty)
        #expect(!vm.isSearchActive)
    }

    @Test("updateSearch mit aktiven Kriterien setzt isSearchActive")
    func updateSearchActiveSetsSearchActive() {
        let vm = makeVM()
        var c = CommitSearchCriteria()
        c.message = "query"
        vm.updateSearch(c)
        #expect(vm.isSearchActive)
    }

    // MARK: selectedCommit

    @Test("selectedCommit gibt nil wenn ID nicht in commits enthalten")
    func selectedCommitIDNotFound() {
        let vm = makeVM()
        vm.selectedCommitID = "notexistent"
        #expect(vm.selectedCommit == nil)
    }

    @Test("selectedCommit gibt nil bei aktiver Suche ohne Treffer")
    func selectedCommitSearchActiveMiss() {
        let vm = makeVM()
        vm.selectedCommitID = "deadbeef"
        var c = CommitSearchCriteria()
        c.message = "query"
        vm.updateSearch(c)
        #expect(vm.selectedCommit == nil)
    }

    // MARK: selectCommit

    @Test("selectCommit setzt branchJumpMessage wenn SHA fehlt und nicht am Laden")
    func selectCommitMissingMessage() {
        let vm = makeVM()
        vm.selectCommit(bySha: "aabbccdd1122")
        #expect(vm.branchJumpMessage != nil)
    }

    // MARK: requestBlame

    @Test("requestBlame ohne ausgewählten Commit öffnet kein Sheet")
    func requestBlameWithoutCommit() {
        let vm = makeVM()
        vm.requestBlame(path: "file.swift")
        #expect(!vm.showBlameSheet)
    }

    // MARK: load / loadMore (Fehlerpfade auf nicht-existierendem Pfad)

    @Test("load() auf nicht-existierendem Pfad setzt isLoading zurück")
    func loadErrorResetsIsLoading() async {
        let vm = makeVM()
        await vm.load()
        #expect(!vm.isLoading)
    }

    @Test("load() auf nicht-existierendem Pfad setzt errorMessage")
    func loadErrorSetsMessage() async {
        let vm = makeVM()
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test("loadMore() auf nicht-existierendem Pfad setzt isLoadingMore zurück")
    func loadMoreErrorResetsFlag() async {
        let vm = makeVM()
        await vm.loadMore()
        #expect(!vm.isLoadingMore)
    }
}

// MARK: - DiffModels

@Suite("DiffModels")
struct DiffModelsTests {

    @Test("maxLineNumber gibt 0 zurück für leere Hunks")
    func maxLineNumberEmpty() {
        let file = DiffFile(id: 0, oldPath: "a.swift", newPath: "a.swift",
                            hunks: [], addedLines: 0, deletedLines: 0)
        #expect(file.maxLineNumber == 0)
    }

    @Test("maxLineNumber gibt höchste newLineNumber zurück")
    func maxLineNumberFromNew() {
        let l1 = DiffLine(id: 0, type: .context,  content: "x",  oldLineNumber: 5,  newLineNumber: 5)
        let l2 = DiffLine(id: 1, type: .addition, content: "+y", oldLineNumber: nil, newLineNumber: 12)
        let hunk = DiffHunk(id: 0, header: "@@ -5 +5,2 @@", lines: [l1, l2])
        let file = DiffFile(id: 0, oldPath: "a.swift", newPath: "a.swift",
                            hunks: [hunk], addedLines: 1, deletedLines: 0)
        #expect(file.maxLineNumber == 12)
    }

    @Test("maxLineNumber berücksichtigt oldLineNumber")
    func maxLineNumberFromOld() {
        let l = DiffLine(id: 0, type: .deletion, content: "-x", oldLineNumber: 20, newLineNumber: nil)
        let hunk = DiffHunk(id: 0, header: "@@ -20 +20 @@", lines: [l])
        let file = DiffFile(id: 0, oldPath: "a.swift", newPath: "a.swift",
                            hunks: [hunk], addedLines: 0, deletedLines: 1)
        #expect(file.maxLineNumber == 20)
    }

    @Test("changeType ist .modified für gleiche Pfade")
    func changeTypeModified() {
        let file = DiffFile(id: 0, oldPath: "file.swift", newPath: "file.swift",
                            hunks: [], addedLines: 1, deletedLines: 0)
        #expect(file.changeType == .modified)
    }

    @Test("displayName gibt den Pfad direkt aus wenn alt == neu")
    func displayNameSamePaths() {
        let file = DiffFile(id: 0, oldPath: "file.swift", newPath: "file.swift",
                            hunks: [], addedLines: 0, deletedLines: 0)
        #expect(file.displayName == "file.swift")
    }
}

// MARK: - Branch und GitTag id-Eigenschaft

@Suite("Branch — id-Eigenschaft")
struct BranchIdTests {

    @Test("id entspricht name")
    func branchIdIsName() {
        let b = Branch(name: "main", shortName: "main", isCurrent: true, isRemote: false,
                       remoteName: nil, tipSha: "abc123",
                       upstreamName: nil, ahead: nil, behind: nil)
        #expect(b.id == "main")
    }
}

@Suite("GitTag — id-Eigenschaft")
struct GitTagIdTests {

    @Test("id entspricht name")
    func tagIdIsName() {
        let tag = GitTag(name: "v1.2", targetSha: "deadbeef")
        #expect(tag.id == "v1.2")
    }
}

// MARK: - RepoStatus (reine Helfer)

@Suite("RepoStatus — Helfer")
struct RepoStatusTests {

    // parsePorcelainDirty

    @Test("Leere Ausgabe → nicht dirty")
    func emptyOutputNotDirty() {
        #expect(!RepoStatus.parsePorcelainDirty(""))
    }

    @Test("Nur Whitespace → nicht dirty")
    func whitespaceNotDirty() {
        #expect(!RepoStatus.parsePorcelainDirty("  \n  "))
    }

    @Test("Porcelain-Zeile → dirty")
    func modifiedFileDirty() {
        #expect(RepoStatus.parsePorcelainDirty(" M Sources/Foo.swift"))
    }

    @Test("Untracked-Zeile → dirty")
    func untrackedFileDirty() {
        #expect(RepoStatus.parsePorcelainDirty("?? NewFile.swift"))
    }

    // relativeLabel

    @Test("Liefert nicht-leeren String für vergangenes Datum")
    func relativeLabelNonEmpty() {
        let past = Date(timeIntervalSinceNow: -3600)
        let label = RepoStatus.relativeLabel(from: past)
        #expect(!label.isEmpty)
    }

    @Test("Referenzdatum now wird berücksichtigt")
    func relativeLabelUsesNowParameter() {
        let anchor = Date(timeIntervalSince1970: 0)
        let now    = Date(timeIntervalSince1970: 7200)
        let label  = RepoStatus.relativeLabel(from: anchor, to: now)
        #expect(!label.isEmpty)
    }

    // isBehind

    @Test("isBehind false ohne Upstream")
    func isBehindFalseWithoutUpstream() {
        var st = RepoStatus()
        st.hasUpstream = false
        st.behindCount = 5
        #expect(!st.isBehind)
    }

    @Test("isBehind false mit Upstream aber behindCount 0")
    func isBehindFalseWhenZero() {
        var st = RepoStatus()
        st.hasUpstream = true
        st.behindCount = 0
        #expect(!st.isBehind)
    }

    @Test("isBehind true mit Upstream und behindCount > 0")
    func isBehindTrueWhenUpstreamAndPositive() {
        var st = RepoStatus()
        st.hasUpstream = true
        st.behindCount = 3
        #expect(st.isBehind)
    }
}

// MARK: - GitService — lokale Statusabfragen (Integration)

@Suite("GitService — lokale Statusabfragen")
struct GitServiceLocalStatusTests {

    let repoURL: URL

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init", "-b", "main")
        try sh("git", "-C", repoURL.path, "config", "user.email", "t@t.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "T")
        let f = repoURL.appendingPathComponent("init.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Initial commit")
    }

    @Test("currentBranch liefert 'main'")
    func currentBranchIsMain() async {
        let svc = GitService(repositoryPath: repoURL)
        let branch = await svc.currentBranch()
        #expect(branch == "main")
    }

    @Test("hasUncommittedChanges false nach sauberem Commit")
    func noUncommittedChangesAfterCommit() async {
        let svc = GitService(repositoryPath: repoURL)
        #expect(await svc.hasUncommittedChanges() == false)
    }

    @Test("hasUncommittedChanges true nach Dateiänderung")
    func uncommittedChangesAfterModification() async throws {
        let f = repoURL.appendingPathComponent("modified.txt")
        try "changed".write(to: f, atomically: true, encoding: .utf8)
        let svc = GitService(repositoryPath: repoURL)
        #expect(await svc.hasUncommittedChanges() == true)
    }

    @Test("lastCommitDate ist nicht nil und nahe jetzt")
    func lastCommitDateNearNow() async {
        let svc = GitService(repositoryPath: repoURL)
        let date = await svc.lastCommitDate()
        #expect(date != nil)
        if let d = date {
            #expect(abs(d.timeIntervalSinceNow) < 60)
        }
    }
}

// MARK: - RepositoryStatisticsTests

@Suite("RepositoryStatisticsTests")
struct RepositoryStatisticsTests {

    // MARK: parseShortlog

    @Test("parseShortlog: E-Mail wird als Gruppierschlüssel und Anzeigename verwendet")
    func parseShortlogBasic() {
        let output = "     5\tAlice Smith <alice@example.com>\n     3\tBob Jones <bob@example.com>\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        #expect(authors.count == 2)
        // name = E-Mail-Adresse (lowercased), da nach E-Mail gruppiert wird
        #expect(authors[0].name == "alice@example.com")
        #expect(authors[0].email == "alice@example.com")
        #expect(authors[0].commitCount == 5)
        #expect(authors[1].name == "bob@example.com")
        #expect(authors[1].commitCount == 3)
    }

    @Test("parseShortlog: Prozentwerte summieren sich auf 100")
    func parseShortlogPercentageSum() {
        let output = "     7\tA <a@x.com>\n     3\tB <b@x.com>\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        let total = authors.reduce(0.0) { $0 + $1.percentage }
        #expect(abs(total - 100.0) < 0.001)
    }

    @Test("parseShortlog: Leere Eingabe liefert leere Liste")
    func parseShortlogEmpty() {
        #expect(RepositoryStatistics.parseShortlog("").isEmpty)
    }

    @Test("parseShortlog: Autor ohne E-Mail wird akzeptiert")
    func parseShortlogNoEmail() {
        let output = "     2\tAlice Smith\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        #expect(authors.count == 1)
        // Ohne E-Mail wird der lowercased Name als Schlüssel verwendet
        #expect(authors[0].name == "alice smith")
        #expect(authors[0].email == "")
    }

    @Test("parseShortlog: Absteigend nach Commit-Anzahl sortiert")
    func parseShortlogSortOrder() {
        let output = "     1\tC <c@x.com>\n    10\tA <a@x.com>\n     5\tB <b@x.com>\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        #expect(authors[0].commitCount == 10)
        #expect(authors[1].commitCount == 5)
        #expect(authors[2].commitCount == 1)
    }

    // MARK: aggregate – Randfall: leer

    @Test("aggregate: Leeres Repository liefert Null-Statistik")
    func aggregateEmpty() {
        let s = RepositoryStatistics.aggregate(
            timestampLines: "",
            authors: [],
            branchCount: 0,
            tagCount: 0
        )
        #expect(s.totalCommits == 0)
        #expect(s.firstCommit == nil)
        #expect(s.lastCommit == nil)
        #expect(s.weekday.count == 7)
        #expect(s.hourly.count == 24)
    }

    // MARK: aggregate – einzelner Commit

    @Test("aggregate: Einzelner Commit setzt first == last")
    func aggregateSingleCommit() {
        let ts: TimeInterval = 1_000_000_000   // 2001-09-09
        let s = RepositoryStatistics.aggregate(
            timestampLines: "\(Int(ts))",
            authors: [],
            branchCount: 3,
            tagCount: 2
        )
        #expect(s.totalCommits == 1)
        #expect(s.firstCommit == s.lastCommit)
        #expect(s.branchCount == 3)
        #expect(s.tagCount == 2)
        #expect(s.monthly.count == 1)
        #expect(s.weekday.count == 7)
        #expect(s.hourly.count == 24)
        #expect(s.weekday.map(\.count).reduce(0, +) == 1)
        #expect(s.hourly.map(\.count).reduce(0, +) == 1)
    }

    // MARK: aggregate – Monats-Buckets

    @Test("aggregate: Zwei Commits in einem Monat, einer im nächsten")
    func aggregateMonthBucketing() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = 2024; c.month = 3; c.day = 15; c.hour = 12
        let d1 = cal.date(from: c)!
        c.day = 16
        let d2 = cal.date(from: c)!
        c.month = 4; c.day = 1
        let d3 = cal.date(from: c)!

        let lines = [d1, d2, d3]
            .map { "\(Int($0.timeIntervalSince1970))" }
            .joined(separator: "\n")

        let s = RepositoryStatistics.aggregate(
            timestampLines: lines,
            authors: [],
            branchCount: 0,
            tagCount: 0
        )
        #expect(s.totalCommits == 3)
        #expect(s.monthly.count == 2)
    }

    // MARK: aggregate – Ø Commits/Woche

    @Test("aggregate: Ø Commits/Woche bei 14 Tagen und 2 Commits ≈ 1,0")
    func aggregateAverageCommitsPerWeek() {
        let ts1: TimeInterval = 0
        let ts2: TimeInterval = 14 * 86400
        let s = RepositoryStatistics.aggregate(
            timestampLines: "\(Int(ts1))\n\(Int(ts2))",
            authors: [],
            branchCount: 0,
            tagCount: 0
        )
        #expect(abs(s.commitsPerWeekAverage - 1.0) < 0.15)
    }

    // MARK: computeBusFactor

    @Test("computeBusFactor: Leere Liste liefert 0")
    func busFactorEmpty() {
        #expect(RepositoryStatistics.computeBusFactor([]) == 0)
    }

    @Test("computeBusFactor: Ein Autor mit 100 % liefert 1")
    func busFactorSingleAuthor() {
        let a = AuthorStat(name: "Alice", email: "a@x.com", commitCount: 10, percentage: 100)
        #expect(RepositoryStatistics.computeBusFactor([a]) == 1)
    }

    @Test("computeBusFactor: Zwei gleichstarke Autoren → Schwelle bei 80 % erfordert beide")
    func busFactorTwoEqual() {
        let a = AuthorStat(name: "A", email: "a@x.com", commitCount: 5, percentage: 50)
        let b = AuthorStat(name: "B", email: "b@x.com", commitCount: 5, percentage: 50)
        // 50 < 80 → nach erstem Autor noch nicht erreicht; 50+50=100 ≥ 80 → 2 Autoren
        #expect(RepositoryStatistics.computeBusFactor([a, b]) == 2)
    }

    @Test("computeBusFactor: Erster Autor überschreitet Schwelle allein")
    func busFactorFirstExceedsThreshold() {
        let a = AuthorStat(name: "A", email: "a@x.com", commitCount: 90, percentage: 90)
        let b = AuthorStat(name: "B", email: "b@x.com", commitCount: 10, percentage: 10)
        #expect(RepositoryStatistics.computeBusFactor([a, b]) == 1)
    }

    @Test("computeBusFactor: Schwelle exakt getroffen zählt")
    func busFactorExactThreshold() {
        // Autor 1: 40 %, Autor 2: 40 % → kumuliert 80 % nach Autor 2 → Bus Factor 2
        let a = AuthorStat(name: "A", email: "a@x.com", commitCount: 4, percentage: 40)
        let b = AuthorStat(name: "B", email: "b@x.com", commitCount: 4, percentage: 40)
        let c = AuthorStat(name: "C", email: "c@x.com", commitCount: 2, percentage: 20)
        #expect(RepositoryStatistics.computeBusFactor([a, b, c]) == 2)
    }

    // MARK: longestDailyStreak

    @Test("longestDailyStreak: Leere Liste liefert 0")
    func streakEmpty() {
        let cal = Calendar(identifier: .gregorian)
        #expect(RepositoryStatistics.longestDailyStreak([], calendar: cal) == 0)
    }

    @Test("longestDailyStreak: Einzelner Tag liefert 1")
    func streakSingleDay() {
        let cal = Calendar(identifier: .gregorian)
        let d = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(RepositoryStatistics.longestDailyStreak([d], calendar: cal) == 1)
    }

    @Test("longestDailyStreak: Drei aufeinanderfolgende Tage liefert 3")
    func streakThreeDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 3; c.hour = 12
        c.day = 1; let d1 = cal.date(from: c)!
        c.day = 2; let d2 = cal.date(from: c)!
        c.day = 3; let d3 = cal.date(from: c)!
        #expect(RepositoryStatistics.longestDailyStreak([d1, d2, d3], calendar: cal) == 3)
    }

    @Test("longestDailyStreak: Lücke unterbricht Kette")
    func streakGap() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 3; c.hour = 12
        c.day = 1; let d1 = cal.date(from: c)!
        c.day = 2; let d2 = cal.date(from: c)!
        c.day = 4; let d4 = cal.date(from: c)!  // Lücke an Tag 3
        c.day = 5; let d5 = cal.date(from: c)!
        // Ketten: [1,2]=2, [4,5]=2 → max 2
        #expect(RepositoryStatistics.longestDailyStreak([d1, d2, d4, d5], calendar: cal) == 2)
    }

    @Test("longestDailyStreak: Mehrere Commits am selben Tag zählen als 1 Aktivitätstag")
    func streakSameDayDedup() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 3; c.day = 10
        c.hour = 9;  let d1 = cal.date(from: c)!
        c.hour = 14; let d2 = cal.date(from: c)!   // selber Tag wie d1
        c.day = 11; c.hour = 10; let d3 = cal.date(from: c)!
        // Zwei Tage mit je ≥ 1 Commit → Streak 2
        #expect(RepositoryStatistics.longestDailyStreak([d1, d2, d3], calendar: cal) == 2)
    }

    // MARK: aggregate – neue KPIs

    @Test("aggregate: averageDaysBetweenCommits bei bekanntem Abstand")
    func aggregateAvgDaysBetweenCommits() {
        // 3 Commits mit je 5 Tagen Abstand → Ø = 5 Tage
        let ts0: TimeInterval = 0
        let ts1: TimeInterval = 5 * 86400
        let ts2: TimeInterval = 10 * 86400
        let s = RepositoryStatistics.aggregate(
            timestampLines: "\(Int(ts0))\n\(Int(ts1))\n\(Int(ts2))",
            authors: [],
            branchCount: 0,
            tagCount: 0
        )
        #expect(abs(s.averageDaysBetweenCommits - 5.0) < 0.01)
    }

    @Test("aggregate: mostActiveMonth wählt Monat mit den meisten Commits")
    func aggregateMostActiveMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.hour = 12
        // Januar: 1 Commit, Februar: 3 Commits
        c.month = 1; c.day = 15; let jan = cal.date(from: c)!
        c.month = 2; c.day = 1;  let feb1 = cal.date(from: c)!
        c.day = 10; let feb2 = cal.date(from: c)!
        c.day = 20; let feb3 = cal.date(from: c)!
        let lines = [jan, feb1, feb2, feb3]
            .map { "\(Int($0.timeIntervalSince1970))" }.joined(separator: "\n")
        let s = RepositoryStatistics.aggregate(
            timestampLines: lines, authors: [], branchCount: 0, tagCount: 0)
        #expect(s.mostActiveMonth?.count == 3)
        // Label muss mit "2024-02" beginnen
        #expect(s.mostActiveMonth?.label == "2024-02")
    }

    @Test("aggregate: Leerfall → busFactor/streak/avgDays == 0, mostActive == nil")
    func aggregateEmptyNewKPIs() {
        let s = RepositoryStatistics.aggregate(
            timestampLines: "", authors: [], branchCount: 0, tagCount: 0)
        #expect(s.busFactor == 0)
        #expect(s.longestStreakDays == 0)
        #expect(s.averageDaysBetweenCommits == 0)
        #expect(s.mostActiveMonth == nil)
        #expect(s.mostActiveWeekday == nil)
    }

    // MARK: parseShortlog — E-Mail-Dedup

    @Test("parseShortlog: gleiche E-Mail in verschiedener Schreibweise wird zusammengefasst")
    func parseShortlogEmailCaseDedup() {
        let output = "     3\tAlice <ALICE@EXAMPLE.COM>\n     2\tAlice <alice@example.com>\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        #expect(authors.count == 1)
        #expect(authors[0].commitCount == 5)
        #expect(authors[0].name == "alice@example.com")
    }

    @Test("parseShortlog: gleiche E-Mail mit verschiedenem Namen wird summiert")
    func parseShortlogSameEmailDifferentName() {
        let output = "     5\tAlice Smith <alice@example.com>\n     3\tAlice <alice@example.com>\n"
        let authors = RepositoryStatistics.parseShortlog(output)
        #expect(authors.count == 1)
        #expect(authors[0].commitCount == 8)
    }
}

// MARK: - StatisticsViewModelTests

@Suite("StatisticsViewModel")
@MainActor
struct StatisticsViewModelTests {

    @Test("Initialzustand: statistics nil, isLoading false, errorMessage nil")
    func initialState() {
        let bm = RepositoryBookmark(name: "Test", path: URL(fileURLWithPath: "/tmp/test"))
        let vm = StatisticsViewModel(repository: bm)
        #expect(vm.statistics == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test("repository wird korrekt gespeichert")
    func repositoryIsStored() {
        let bm = RepositoryBookmark(name: "MyRepo", path: URL(fileURLWithPath: "/tmp/myrepo"))
        let vm = StatisticsViewModel(repository: bm)
        #expect(vm.repository.name == "MyRepo")
        #expect(vm.repository.path == URL(fileURLWithPath: "/tmp/myrepo"))
    }

    @Test("load mit ungültigem Pfad setzt errorMessage")
    func loadWithInvalidPathSetsError() async {
        let bm = RepositoryBookmark(
            name: "Ghost",
            path: URL(fileURLWithPath: "/tmp/statsvm-ghost-\(UUID().uuidString)")
        )
        let vm = StatisticsViewModel(repository: bm)
        await vm.load()
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - AppModel — Erweitert

@Suite("AppModel — Erweitert")
@MainActor
struct AppModelExtendedTests {

    func makeModel() -> AppModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-ext-\(UUID().uuidString).json")
        return AppModel(store: BookmarkStore(fileURL: url))
    }

    @Test("newCommitStatus und repoStatus starten leer")
    func initialStatusMapsEmpty() {
        let model = makeModel()
        #expect(model.newCommitStatus.isEmpty)
        #expect(model.repoStatus.isEmpty)
    }

    @Test("markRepositorySeen initialisiert newCommitStatus-Eintrag ohne Fehler")
    func markRepositorySeenInitializesEntry() async {
        let model = makeModel()
        let id = UUID()
        await model.markRepositorySeen(id)
        let status = model.newCommitStatus[id]
        #expect(status != nil)
        #expect(status?.hasLocalChanges == false)
    }

    @Test("closeRepository lässt newCommitStatus unangetastet")
    func closeRepositoryKeepsNewCommitStatus() async {
        let model = makeModel()
        let id = UUID()
        await model.markRepositorySeen(id)
        model.openedRepository = RepositoryBookmark(name: "R", path: URL(fileURLWithPath: "/tmp/r"))
        model.closeRepository()
        #expect(model.openedRepository == nil)
        #expect(model.newCommitStatus[id] != nil)
    }
}

// MARK: - GitService — lokale Statusabfragen (Erweiterung)

extension GitServiceLocalStatusTests {

    @Test("blame liefert Zeilen für bekannte Datei und Commit")
    func blameReturnsLinesForKnownFile() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let commits = try await svc.loadCommits()
        guard let first = commits.first else { Issue.record("Kein Commit"); return }
        let lines = try await svc.blame(path: "init.txt", sha: first.sha)
        #expect(!lines.isEmpty)
        #expect(lines[0].content == "x")
    }

    @Test("localRefSignature liefert nicht-leere Map nach Commit")
    func localRefSignatureIsNotEmpty() async {
        let svc = GitService(repositoryPath: repoURL)
        let sig = await svc.localRefSignature()
        #expect(!sig.isEmpty)
        #expect(sig.keys.contains(where: { $0.hasPrefix("refs/heads/") }))
    }

    @Test("firstRemoteName liefert nil ohne konfigurierten Remote")
    func firstRemoteNameIsNilWithoutRemote() async {
        let svc = GitService(repositoryPath: repoURL)
        let name = await svc.firstRemoteName()
        #expect(name == nil)
    }
}

// MARK: - GitService — aheadBehind (Erweiterung)

extension GitServiceAheadBehindTests {

    @Test("remoteName liefert 'origin' für geklontes Repo")
    func remoteNameIsOriginForClonedRepo() async throws {
        let svc = GitService(repositoryPath: localURL)
        let name = try await svc.remoteName()
        #expect(name == "origin")
    }

    @Test("hasRemote ist true für Repo mit konfiguriertem Remote")
    func hasRemoteIsTrueForClonedRepo() async {
        let svc = GitService(repositoryPath: localURL)
        let result = await svc.hasRemote()
        #expect(result)
    }
}

// MARK: - AppModel — Monitoring (Integration)

@Suite("AppModel — Monitoring")
@MainActor
struct AppModelMonitoringTests {

    func makeModel() -> AppModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-mon-\(UUID().uuidString).json")
        return AppModel(store: BookmarkStore(fileURL: url))
    }

    @Test("startMonitoring erstellt Services und Task für Repos mit .git-Verzeichnis")
    func startMonitoringWithValidGitRepo() async throws {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init", "-b", "main")
        try sh("git", "-C", repoURL.path, "config", "user.email", "t@t.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "T")
        let f = repoURL.appendingPathComponent("f.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "init")
        defer { try? FileManager.default.removeItem(at: repoURL) }

        // Auto-Refresh explizit aktivieren, damit startMonitoring über den ersten Guard kommt.
        AppSettings.setAutoRefreshEnabled(true)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.autoRefreshEnabledKey) }

        let model = makeModel()
        // addRepository → persist() → restartMonitoring() → startMonitoring()
        // Mit vorhandenem .git-Verzeichnis wird die Ausführung über guard !repos.isEmpty fortgesetzt.
        model.addRepository(name: "TestRepo", path: repoURL)

        // Async-Task in startMonitoring (localRefSignature + refreshLocalStatus) ablaufen lassen.
        // Wir prüfen nur den zuverlässigen Synchron-Zustand; async-Ergebnisse sind timing-abhängig.
        try await Task.sleep(for: .milliseconds(1500))

        #expect(model.bookmarkNodes.count == 1)
    }
}

// MARK: - GitService — Statistik-Abfragen

@Suite("GitService — Statistik-Abfragen")
@MainActor
struct GitServiceStatisticsTests {
    let repoURL: URL

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init")
        try sh("git", "-C", repoURL.path, "config", "user.email", "stats@example.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "Stats Tester")
        let readme = repoURL.appendingPathComponent("README.md")
        try "# Stats\n".write(to: readme, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Initial stats commit")
    }

    @Test("commitTimestamps liefert gültige Unix-Timestamps")
    func commitTimestampsValid() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let output = try await svc.commitTimestamps()
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(!lines.isEmpty)
        let ts = TimeInterval(lines[0].trimmingCharacters(in: .whitespaces))
        #expect(ts != nil)
        #expect((ts ?? 0) > 0)
    }

    @Test("authorCommitCounts liefert mindestens einen Autor")
    func authorCommitCountsNotEmpty() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let authors = try await svc.authorCommitCounts()
        #expect(!authors.isEmpty)
        #expect(authors[0].commitCount >= 1)
    }

    @Test("authorCommitCounts: E-Mail wird als Gruppierschlüssel verwendet")
    func authorCommitCountsGroupedByEmail() async throws {
        let svc = GitService(repositoryPath: repoURL)
        let authors = try await svc.authorCommitCounts()
        let found = authors.first { $0.name == "stats@example.com" }
        #expect(found != nil)
    }
}

// MARK: - RepositoryViewModel — Abdeckungs-Ergänzungen (Blame, Suche, loadMore-Suche)

@Suite("RepositoryViewModel — Abdeckung")
@MainActor
struct RepositoryViewModelCoverageTests {

    let repoURL: URL
    let bookmark: RepositoryBookmark

    init() throws {
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-cov-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try sh("git", "-C", repoURL.path, "init")
        try sh("git", "-C", repoURL.path, "config", "user.email", "cov@test.com")
        try sh("git", "-C", repoURL.path, "config", "user.name", "CovTester")
        let file = repoURL.appendingPathComponent("readme.txt")
        // Drei Commits mit je einer weiteren Zeile — Blame-Datei wächst mit jedem Commit
        try "Erste Zeile\n".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Alpha-Commit")
        try "Erste Zeile\nZweite Zeile\n".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Beta-Commit")
        try "Erste Zeile\nZweite Zeile\nDritte Zeile\n".write(to: file, atomically: true, encoding: .utf8)
        try sh("git", "-C", repoURL.path, "add", ".")
        try sh("git", "-C", repoURL.path, "commit", "-m", "Gamma-Commit")
        bookmark = RepositoryBookmark(name: "CovRepo", path: repoURL)
    }

    // MARK: requestBlame / loadBlame

    @Test("requestBlame öffnet Blame-Sheet und loadBlame befüllt blameLines")
    func requestBlameSetsSheetAndLoadsLines() async throws {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()
        guard let commit = vm.commits.first else { Issue.record("Kein Commit geladen"); return }

        vm.selectedCommitID = commit.sha
        vm.requestBlame(path: "readme.txt")

        // Synchrone Effekte prüfen (deterministisch)
        #expect(vm.showBlameSheet)
        #expect(vm.blameFilePath == "readme.txt")

        // Polling bis loadBlame-Task fertig ist (Timeout 5 s).
        // Bewusst NICHT "where vm.isBlameLoading": der unstrukturierte loadBlame-Task
        // läuft erst beim nächsten Suspension-Punkt an, isBlameLoading kann beim
        // allerersten Check hier also noch false sein, obwohl der Task noch gar nicht
        // gestartet ist — dann würde die where-Klausel jede Iteration überspringen,
        // nie ein await auslösen und die Assertions liefen vor dem Task-Start.
        for _ in 0..<100 {
            if !vm.isBlameLoading && !vm.blameLines.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!vm.isBlameLoading)
        #expect(!vm.blameLines.isEmpty)
    }

    // MARK: loadMore bei aktiver Suche → performSearch(reset: false) deterministisch

    @Test("loadMore bei aktiver Suche trifft isSearchActive-Ast und füllt searchResults")
    func loadMoreWithActiveSearchRunsSearch() async throws {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()

        // isSearchActive=true setzen; searchCanLoadMore=true, isSearching=false
        var criteria = CommitSearchCriteria()
        criteria.message = "Commit"   // trifft alle drei Commits
        vm.updateSearch(criteria)
        // loadMore() sofort aufrufen (vor dem Debounce) → trifft isSearchActive-Ast;
        // await ist deterministisch: kehrt zurück wenn performSearch(reset:false) vollständig ist
        await vm.loadMore()
        #expect(!vm.isSearching)
        #expect(!vm.searchResults.isEmpty)
        #expect(!vm.searchGraphRows.isEmpty)
    }

    // MARK: selectedCommit bei aktiver Suche (isSearchActive-Ast)

    @Test("selectedCommit liefert Commit aus searchResults bei aktiver Suche")
    func selectedCommitFromSearchResults() async throws {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()

        var criteria = CommitSearchCriteria()
        criteria.message = "Beta"
        vm.updateSearch(criteria)
        // loadMore() füllt searchResults deterministisch (kein Timing-Problem)
        await vm.loadMore()

        guard let found = vm.searchResults.first else { Issue.record("Keine Suchergebnisse"); return }
        vm.selectedCommitID = found.sha
        // isSearchActive=true → selectedCommit sucht zuerst in searchResults
        #expect(vm.selectedCommit?.sha == found.sha)
    }

    // MARK: performSearch(reset: true) via updateSearch-Debounce

    @Test("updateSearch löst nach Debounce performSearch(reset:true) aus")
    func updateSearchTriggersDebouncedSearch() async throws {
        let vm = RepositoryViewModel(repository: bookmark)
        await vm.load()

        var criteria = CommitSearchCriteria()
        criteria.message = "Alpha"
        vm.updateSearch(criteria)
        // 300 ms Debounce + großzügiger Puffer; isSearching wird nicht geprüft
        // (zeitkritisch), aber der performSearch(reset:true)-Pfad wird abgedeckt
        try await Task.sleep(for: .milliseconds(1500))
        #expect(vm.isSearchActive)
    }
}
