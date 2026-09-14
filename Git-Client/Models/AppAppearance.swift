//
//  AppAppearance.swift
//  Git-Client
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Wie System"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }

    /// nil bedeutet: dem System folgen. Sonst festes Farbschema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Entsprechende NSAppearance für AppKit; nil = dem System folgen.
    /// Wird benötigt, damit semantische NSColor-Werte (z.B. .labelColor)
    /// nach jedem Erscheinungsbild-Wechsel korrekt auflösen.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
