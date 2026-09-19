//
//  CommandPaletteResult.swift
//  Git-Client
//
//  Wertetyp für einen Treffer der Befehlspalette (⌘K) — Repository, Branch, Tag
//  oder Commit. Rein funktional (Filtern), kein I/O — vollständig unit-testbar
//  ohne SwiftUI-Kontext.
//

import Foundation

nonisolated enum CommandPaletteResult: Identifiable {
    case repository(RepositoryBookmark)
    case branch(Branch)
    case tag(GitTag)
    case commit(Commit)

    var id: String {
        switch self {
        case .repository(let r): "repo-\(r.id.uuidString)"
        case .branch(let b): "branch-\(b.id)"
        case .tag(let t): "tag-\(t.id)"
        case .commit(let c): "commit-\(c.id)"
        }
    }

    /// SF-Symbol-Name für die Zeilendarstellung.
    var symbolName: String {
        switch self {
        case .repository: "externaldrive"
        case .branch: "arrow.triangle.branch"
        case .tag: "tag"
        case .commit: "circle.fill"
        }
    }

    var title: String {
        switch self {
        case .repository(let r): r.name
        case .branch(let b): b.shortName
        case .tag(let t): t.name
        case .commit(let c): c.subject
        }
    }

    var subtitle: String {
        switch self {
        case .repository(let r): r.path.path
        case .branch(let b):
            b.isRemote ? "Remote-Branch\(b.remoteName.map { " · \($0)" } ?? "")" : "Branch"
        case .tag: "Tag"
        case .commit(let c): c.shortSha
        }
    }
}

extension CommandPaletteResult {
    /// Baut die Trefferliste der Befehlspalette.
    ///
    /// Repositories werden immer durchsucht (auch bei leerer Suche — zeigt dann
    /// alle Bookmarks). Branches/Tags/Commits werden nur bei nicht-leerer Suche
    /// einbezogen und nur, wenn ein Repository geöffnet ist (`branches`/`tags`/
    /// `commits` sind dann bereits geladene Daten, kein zusätzlicher git-Aufruf).
    ///
    /// Matching ist bewusst einfaches, case-insensitives Teilstring-Matching
    /// (kein Fuzzy-Subsequence-Scoring) — vorhersehbar und ausreichend für
    /// Repository-/Branch-/Tag-/Commit-Namen.
    static func search(
        query: String,
        repositories: [RepositoryBookmark],
        branches: [Branch],
        tags: [GitTag],
        commits: [Commit],
        limitPerCategory: Int = 8
    ) -> [CommandPaletteResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let repoMatches = repositories
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .prefix(limitPerCategory)
            .map(CommandPaletteResult.repository)

        guard !q.isEmpty else { return Array(repoMatches) }

        let branchMatches = branches
            .filter { $0.shortName.lowercased().contains(q) }
            .prefix(limitPerCategory)
            .map(CommandPaletteResult.branch)

        let tagMatches = tags
            .filter { $0.name.lowercased().contains(q) }
            .prefix(limitPerCategory)
            .map(CommandPaletteResult.tag)

        let commitMatches = commits
            .filter { $0.subject.lowercased().contains(q) || $0.shortSha.hasPrefix(q) }
            .prefix(limitPerCategory)
            .map(CommandPaletteResult.commit)

        return Array(repoMatches) + Array(branchMatches) + Array(tagMatches) + Array(commitMatches)
    }
}
