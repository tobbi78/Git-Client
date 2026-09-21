//
//  BranchTree.swift
//  Git-Client
//
//  Gruppiert Branches in einen Ordner-Baum (eine Ebene tief, gesplittet am ersten
//  "/" im Namen) für die Sidebar-Anzeige. Rein funktional, kein I/O — vollständig
//  unit-testbar.
//

import Foundation

nonisolated struct BranchLeaf: Identifiable, Sendable {
    let branch: Branch
    let displayName: String
    var id: String { branch.id }
}

nonisolated enum BranchTreeNode: Identifiable, Sendable {
    case leaf(BranchLeaf)
    case folder(name: String, children: [BranchLeaf])

    var id: String {
        switch self {
        case .leaf(let l): return l.id
        case .folder(let name, _): return "folder:\(name)"
        }
    }

    var sortKey: String {
        switch self {
        case .leaf(let l): return l.displayName
        case .folder(let name, _): return name
        }
    }
}

nonisolated enum BranchTree {
    /// Gruppiert `branches` anhand des ersten "/" im per `nameOf` gewählten Namen in
    /// Ordner (genau eine Ebene tief — ein Name wie "feature/foo/bar" landet als
    /// Blatt "foo/bar" im Ordner "feature", nicht weiter verschachtelt) und sortiert
    /// Ordner und Top-Level-Blätter gemeinsam lokalisiert case-insensitiv.
    static func build(_ branches: [Branch], nameOf: (Branch) -> String) -> [BranchTreeNode] {
        var folderMap: [String: [BranchLeaf]] = [:]
        var topLevel: [BranchLeaf] = []

        for branch in branches {
            let name = nameOf(branch)
            if let slashIdx = name.firstIndex(of: "/") {
                let folderName = String(name[..<slashIdx])
                let childName = String(name[name.index(after: slashIdx)...])
                folderMap[folderName, default: []].append(BranchLeaf(branch: branch, displayName: childName))
            } else {
                topLevel.append(BranchLeaf(branch: branch, displayName: name))
            }
        }

        var nodes = topLevel.map { BranchTreeNode.leaf($0) }
        for (folderName, children) in folderMap {
            nodes.append(.folder(name: folderName, children: children))
        }
        return nodes.sorted {
            $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
        }
    }
}
