//
//  Git_ClientTests.swift
//  Git-ClientTests
//

import Testing
import Foundation
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

@Suite("AppSettings")
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
