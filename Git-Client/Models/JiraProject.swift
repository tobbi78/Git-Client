//
//  JiraProject.swift
//  Git-Client
//
//  Repräsentiert ein konfiguriertes JIRA-Projekt mit Key und Beschreibung.
//

import Foundation

nonisolated struct JiraProject: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var key: String = ""          // z.B. "PROJ"
    var description: String = ""  // z.B. "Payment Platform"
}
