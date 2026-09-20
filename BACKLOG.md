# Git-Client — Feature- & Optimierungs-Backlog

Stand: 2026-09-19. Priorisiert nach Nutzen/Aufwand, nicht nach Datum. Dies ist ein
internes Planungsdokument (kein Nutzer-Feature-Versprechen) — Einträge werden bei
Bedarf verworfen, umsortiert oder ergänzt.

**Status-Pflege:** Wird die Bearbeitung eines Punkts begonnen (Branch angelegt),
Status auf "🔧 In Arbeit" setzen. Nach dem Merge auf "✅ Erledigt" setzen.

**Randbedingung, die alle Vorschläge respektieren:** Git-Client bleibt ein reiner
Lese-/Betrachtungs-Client. Kein Commit, kein Stage, kein Push, kein Merge/Rebase,
keine Konfliktauflösung — siehe Schreib-Policy. Vorschläge, die dagegen verstoßen
würden, stehen am Ende explizit als *nicht vorgeschlagen* mit Begründung, statt sie
einfach wegzulassen.

---

## Tier 1 — Hoher Nutzen, geringer/mittlerer Aufwand (zuerst)

| # | Status | Idee | Kategorie | Aufwand | Warum jetzt |
|---|---|---|---|---|---|
| 1 | Offen | **Tastatur-Bedienung nachrüsten**: ⌘R (neu laden), ⌘F (Suche fokussieren), ↑/↓-Navigation in der Commit-Liste, ⌘C (SHA kopieren) | Feature | Klein | App hat aktuell **keine** Shortcuts außer Sheet-Standardaktionen (⏎/⎋) — für eine native Mac-App eine auffällige Lücke im Alltagsgebrauch. |
| 2 | ✅ Erledigt | **Kopieren-Affordanzen**: SHA, Branch-/Tag-Name, Commit-Nachricht per Klick/Kontextmenü in Zwischenablage | Feature | Klein | Sehr häufige Aktion in jedem Git-Client, fehlt komplett. |
| 3 | ✅ Erledigt | **"Im Terminal öffnen"** Kontextmenü-Eintrag pro Repository (neben dem schon vorhandenen "Im Finder zeigen") | Feature | Klein (NSWorkspace) | Trivial umzusetzen, spart bei Bedarf den Wechsel zur Shell. |
| 22 | ✅ Erledigt | **"Im Finder zeigen"** per Rechtsklick auf eine Datei in der Diff-Dateiliste | Feature | Klein (NSWorkspace, gleiches Muster wie die schon vorhandene Repo-Ebene in `RepositoryBrowserView`) | Ergänzt die bestehende Repo-Ebene-Aktion um die Datei-Ebene — nützlich, um eine geänderte Datei direkt im Finder zu öffnen. |
| 4 | Offen | **Favoriten/Angepinnte Repositories** — oben in der Übersicht fixiert, unabhängig von Ordnerstruktur | Feature | Klein–Mittel | Bei vielen Repos schneller Zugriff auf die 2–3 täglich genutzten. |
| 5 | ✅ Erledigt | **`AppSettings` dependency-injectable machen** (statt hartkodiertem `UserDefaults.standard`) | Optimierung | Mittel | Behebt die *Ursache* der JIRA-Settings-Bug-Klasse strukturell, statt nur das Symptom (der `withRestoredDefaults`-Test-Helfer bleibt ein Pflaster). Macht `SettingsView`/Tests robuster gegen zukünftige ähnliche Bugs. |
| 6 | Offen | **Testabdeckung für `clone`/`fetch`/`fastForward`/`remoteHeads`** (aktuell 0 %) | Optimierung | Mittel | Einzige verbliebenen "kalten" Stellen in `GitService`; Netzwerk-Anteil lässt sich über eine lokale `file://`-Remote-Fixture (temporäres zweites Git-Repo) testen, ohne echtes Netz. |

## Tier 2 — Hoher Nutzen, mittlerer Aufwand

| # | Status | Idee | Kategorie | Aufwand | Warum |
|---|---|---|---|---|---|
| 7 | Offen | **Datei-Historie ("Follow")**: `git log --follow -- <pfad>` ab einem Kontextmenü-Eintrag in der Diff-Dateiliste | Feature | Mittel (neue `GitService`-Methode + Wiederverwendung von `GitLogParser`) | Klassisches, rein lesendes Git-Client-Feature, das bislang fehlt. |
| 8 | Offen | **Datei-Inhalt zu einem Commit ansehen** (`git show <sha>:<pfad>`), nicht nur den Diff-Hunk | Feature | Mittel | Ergänzt Blame/Diff sinnvoll — ganze Datei zu einem Zeitpunkt betrachten. |
| 9 | Offen | **Beliebige Commits/Branches vergleichen** (`git diff A..B`), nicht nur Commit-vs-Parent | Feature | Mittel–Hoch (UI zur Ref-Auswahl) | Sehr gängiger Workflow ("was hat sich zwischen main und feature-x geändert"), aktuell nicht abbildbar. |
| 10 | Offen | **"Verwerfen & synchronisieren"-Aktion**: expliziter Hard-Reset auf den Upstream-Stand | Feature | Mittel | Setzt die bereits **beschlossene** Schreib-Policy-Ausnahme tatsächlich um — aktuell existiert nur Fetch + Fast-Forward-Pull (schlägt bei Divergenz fehl), der abgestimmte "Remote überschreibt lokal"-Fall ist noch nicht gebaut. |
| 11 | ✅ Erledigt | **Befehlspalette (⌘K)**: Repo/Branch/Tag/Commit per Fuzzy-Suche direkt ansteuern | Feature | Mittel–Hoch | Skaliert gut mit wachsender Repo-/Commit-Zahl, modernes Bedienmuster. |
| 12 | Offen | **Statistiken exportieren** (PNG/PDF/CSV) aus dem Statistik-Fenster | Feature | Klein–Mittel (`ImageRenderer` für Swift Charts) | Swift Charts sind schon da, Export ist ein kleiner Aufsatz mit gutem Nutzen (Teilen/Reporting). |

## Tier 3 — Wertvoll, aber größerer Aufwand oder spekulativerer Nutzen

| # | Status | Idee | Kategorie | Aufwand | Hinweis |
|---|---|---|---|---|---|
| 13 | Offen | **Stash-Liste (nur lesend)**: `git stash list`/`show` in der Seitenleiste | Feature | Mittel | Reine Anzeige, keine Apply/Drop-Aktion — bleibt damit innerhalb der Schreib-Policy. |
| 14 | Offen | **Lokalisierung (Englisch)** | Feature | Groß (~150–250 UI-Strings) | Das Projekt hat gerade erst `STRING_CATALOG_GENERATE_SYMBOLS` aktiviert — ein String-Catalog-Umzug (.xcstrings) ist der naheliegende erste Schritt, unabhängig davon, ob am Ende tatsächlich übersetzt wird. Nur relevant, falls die App über deinen eigenen Gebrauch hinaus geteilt werden soll. |
| 15 | Offen | **Accessibility-Durchgang** (VoiceOver-Labels, Dynamic Type, Kontrast) | Optimierung | Mittel | Dafür existieren bereits fertige Skills in dieser Umgebung (Dynamic-Type-, VoiceOver-, Kontrast-Spezialisten) — Aufwand ist niedriger als er aussieht. |
| 16 | Offen | **Menu-Bar-Extra / Dock-Badge** mit Gesamtzahl "neuer Commits" über alle Repos | Feature | Mittel–Hoch | Daten sind durch das bestehende Auto-Refresh-Badge bereits vorhanden, nur die Präsentation fehlt. |
| 17 | Offen | **`CommitGraphBuilder`-Lane-Lookup optimieren** (`firstIndex(of:)` → Dictionary, O(L)→O(1) pro Commit) | Optimierung | Klein | Nur relevant, falls du bei sehr breiten Historien (viele lange parallele Branches) tatsächlich Ruckeln bemerkst — aktuell kein bekanntes Problem, rein vorbeugend. |

## Tier 4 — Nice-to-have / spekulativ (niedrige Priorität)

| # | Status | Idee | Kategorie | Hinweis |
|---|---|---|---|---|
| 18 | Offen | **Reflog-Viewer** (nur lesend) | Feature | Power-User-Feature, geringe erwartete Nutzungshäufigkeit. |
| 19 | Offen | **Shortcuts/App-Intents-Integration** ("Öffne Repository X" als Siri-Kurzbefehl) | Feature | Nettes Differenzierungsmerkmal, aber für ein Solo-Tool fraglicher ROI. |
| 20 | Offen | **WidgetKit-Widget** mit Repo-Status auf dem Schreibtisch | Feature | Höherer Aufwand relativ zum Nutzen bei einem Ein-Personen-Tool. |
| 21 | Offen | **Submodule-Erkennung** (nur lesend) | Feature | Nur relevant, falls deine Repos tatsächlich Submodule nutzen. |

---

## Explizit NICHT vorgeschlagen (Verstoß gegen Schreib-Policy)

Diese klassischen Git-Client-Features fehlen bewusst, nicht aus Vergessenheit:
Interaktives Staging, Commit erstellen, Push, Merge/Rebase, Cherry-Pick,
Stash Apply/Drop/Pop (Stash **anzeigen** ist ok, s. Tier 3 #13 — Stash **verändern**
nicht), Branch/Tag erstellen oder löschen, Konfliktauflösung. Falls sich die
Schreib-Policy jemals ändern sollte, wäre das ein bewusster, separat zu
entscheidender Schritt — kein Nachrüsten "nebenbei".

## Methodik-Hinweis

Diese Liste basiert auf einer Bestandsaufnahme aller aktuell existierenden
UI-Aktionen (`MainWindowView`, `DiffView`, `RepositoryBrowserView`,
`CommitGraphView`, `BlameView`, `CloneRepositoryView`, `StatisticsView`,
`SettingsView`) und der von `GitService` bereits gekapselten Git-Kommandos, um
Doppelvorschläge zu vermeiden. Einziger vorhandener TODO im Code:
`AppModel.swift:247` (Remote-Poll-Einschränkung, bereits im Memory-Backlog erfasst,
hier nicht erneut aufgeführt).
