//
//  MainWindowView.swift
//  Git-Client
//
//  Sourcetree-Layout:
//  ┌──────────────┬────────────────────────────────┐
//  │              │  Commit-Liste (oben)            │
//  │   Sidebar    ├────────────────────────────────│
//  │  (voll hoch) │  Diff / Detail (unten, breit)  │
//  └──────────────┴────────────────────────────────┘
//

import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel
    let repository: RepositoryBookmark

    @State private var isBranchesExpanded = false
    @State private var isTagsExpanded = false
    @State private var expandedRemotes: [String: Bool] = [:]

    // Breite der Graph-Spalte in der Commit-Liste; per Drag ziehbar
    @State private var graphColumnWidth: CGFloat = 200
    @State private var graphColumnWidthAtDragStart: CGFloat = 200

    // Suche / Filter
    @State private var criteria = CommitSearchCriteria()
    @State private var showAdvancedFilter = false

    @Environment(\.openWindow) private var openWindow

    private var vm: RepositoryViewModel? { appModel.repositoryViewModel }

    private var subtitleText: String {
        guard let vm else { return repository.path.path }
        if vm.isLoading { return "Wird geladen…" }
        if vm.isSearchActive {
            if vm.isSearching { return "Suche…" }
            let count = vm.searchResults.count
            let label = count == 1 ? "1 Treffer" : "\(count) Treffer"
            return vm.visibleCanLoadMore ? "\(label) (mehr verfügbar)" : label
        }
        let count = vm.commits.count
        let branch = vm.branches.first(where: \.isCurrent)?.name ?? ""
        if count == 0 { return repository.path.path }
        let commitLabel = count == 1 ? "1 Commit" : "\(count) Commits"
        return branch.isEmpty ? commitLabel : "\(branch)  ·  \(commitLabel)"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VSplitView {
                commitPane
                    .frame(minHeight: 200)
                commitDetail
                    .frame(minHeight: 180)
            }
            // Mindestbreite erzwingen, damit die Detail-Spalte beim Öffnen
            // sofort breit genug ist — unabhängig davon ob ein Commit ausgewählt ist.
            .frame(minWidth: 640, maxWidth: .infinity)
        }
        .navigationTitle(repository.name)
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Repositories", systemImage: "chevron.left") {
                    appModel.closeRepository()
                }
                .help("Zurück zur Repository-Übersicht")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Statistiken", systemImage: "chart.bar.xaxis") {
                    openWindow(id: "repo-statistics", value: repository)
                }
                .help("Repository-Statistiken in einem neuen Fenster anzeigen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Im Terminal öffnen", systemImage: "terminal") {
                    TerminalService.open(directory: repository.path)
                }
                .help("Repository-Ordner in der Terminal-App öffnen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Remote im Browser öffnen", systemImage: "safari") {
                    Task {
                        if let url = await vm?.remoteWebURL() {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .disabled(!(vm?.hasRemote ?? false))
                .help("Webseite des Remotes (origin) im Browser öffnen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Neu laden", systemImage: "arrow.clockwise") {
                    Task { await vm?.load() }
                }
                .disabled(vm?.isLoading ?? true)
                .help("Commits, Branches und Tags neu laden")
            }
        }
        // Fenster beim Öffnen eines Repositories auf Mindestgröße bringen.
        // .frame(minWidth:) auf einem nicht-root-View erzwingt keine Fenster-Vergrößerung;
        // daher direkter NSWindow-Zugriff per keyWindow.
        .onAppear {
            DispatchQueue.main.async {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                let minW: CGFloat = 900
                let minH: CGFloat = 600
                if window.frame.size.width < minW || window.frame.size.height < minH {
                    window.setContentSize(CGSize(
                        width:  max(minW, window.frame.size.width),
                        height: max(minH, window.frame.size.height)
                    ))
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            localBranchesSection
            remoteBranchesSections
            tagsSection
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Unkommittete Änderungen",
            isPresented: Binding(
                get: { vm?.pendingCheckoutBranch != nil },
                set: { if !$0 { vm?.cancelPendingCheckout() } }
            ),
            titleVisibility: .visible,
            presenting: vm?.pendingCheckoutBranch
        ) { branch in
            Button("Änderungen verwerfen und wechseln", role: .destructive) {
                Task { await vm?.confirmCheckoutDiscardingChanges(branch) }
            }
            Button("Abbrechen", role: .cancel) {
                vm?.cancelPendingCheckout()
            }
        } message: { branch in
            Text("Es gibt unkommittete Änderungen. Beim Wechsel zu \(branch.shortName) werden sie verworfen.")
        }
        .alert(
            "Branch-Wechsel fehlgeschlagen",
            isPresented: Binding(
                get: { vm?.checkoutErrorMessage != nil },
                set: { if !$0 { vm?.checkoutErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm?.checkoutErrorMessage ?? "")
        }
        .confirmationDialog(
            "Fast-Forward nicht möglich",
            isPresented: Binding(
                get: { vm?.pendingHardReset ?? false },
                set: { if !$0 { vm?.cancelPendingHardReset() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Lokalen Stand verwerfen und synchronisieren", role: .destructive) {
                Task { await vm?.confirmHardResetToUpstream() }
            }
            Button("Abbrechen", role: .cancel) {
                vm?.cancelPendingHardReset()
            }
        } message: {
            Text("Lokale Commits oder Änderungen weichen vom Server ab. Beim Fortfahren wird der lokale Stand verworfen und durch den Server-Stand ersetzt.")
        }
        .confirmationDialog(
            deleteBranchDialogTitle,
            isPresented: Binding(
                get: { vm?.pendingBranchDeletion != nil },
                set: { if !$0 { vm?.cancelPendingBranchDeletion() } }
            ),
            titleVisibility: .visible,
            presenting: vm?.pendingBranchDeletion
        ) { pending in
            // `pending` kommt aus der `presenting:`-Variante von confirmationDialog und
            // bleibt stabil, selbst wenn SwiftUI beim Antippen dieses Buttons
            // `pendingBranchDeletion` über den isPresented-Dismiss-Handler bereits auf
            // nil setzt — siehe Kommentar an performPendingBranchDeletion.
            Button(deleteBranchConfirmButtonLabel(for: pending), role: .destructive) {
                Task { await vm?.performPendingBranchDeletion(pending) }
            }
            Button("Abbrechen", role: .cancel) {
                vm?.cancelPendingBranchDeletion()
            }
        } message: { pending in
            Text(deleteBranchDialogMessage(for: pending))
        }
        .alert(
            "Branch löschen fehlgeschlagen",
            isPresented: Binding(
                get: { vm?.deleteBranchErrorMessage != nil },
                set: { if !$0 { vm?.deleteBranchErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm?.deleteBranchErrorMessage ?? "")
        }
    }

    private var deleteBranchDialogTitle: String {
        if case .confirmForce = vm?.pendingBranchDeletion { return "Branch nicht vollständig gemerged" }
        return "Branch löschen"
    }

    private func deleteBranchConfirmButtonLabel(for pending: PendingBranchDeletion) -> String {
        if case .confirmForce = pending { return "Trotzdem löschen" }
        return "Löschen"
    }

    private func deleteBranchDialogMessage(for pending: PendingBranchDeletion) -> String {
        switch pending {
        case .confirmSafe(let branch):
            return "Soll der lokale Branch \"\(branch.shortName)\" wirklich gelöscht werden?"
        case .confirmForce(let branch):
            return "\"\(branch.shortName)\" enthält Commits, die auf keinem anderen Branch vorhanden sind. Beim Löschen gehen sie verloren."
        }
    }

    @ViewBuilder
    private var localBranchesSection: some View {
        DisclosureGroup(isExpanded: $isBranchesExpanded) {
            if let vm, !vm.localBranchTree.isEmpty {
                let localBranchCount = vm.branches.filter { !$0.isRemote }.count
                ForEach(vm.localBranchTree) { node in
                    branchNodeRow(node, localBranchCount: localBranchCount)
                }
            } else {
                Text(vm == nil ? "Wird geladen…" : "Keine Branches")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } label: {
            Label("Branches", systemImage: "arrow.triangle.branch")
                .font(.callout.weight(.semibold))
        }
    }

    @ViewBuilder
    private var remoteBranchesSections: some View {
        ForEach(vm?.remoteNames ?? [], id: \.self) { remoteName in
            DisclosureGroup(isExpanded: remoteBinding(for: remoteName)) {
                ForEach(vm?.remoteBranchTrees[remoteName] ?? []) { node in
                    branchNodeRow(node)
                }
            } label: {
                Label("Remotes / \(remoteName)", systemImage: "network")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    private func remoteBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { expandedRemotes[name] ?? true },
            set: { expandedRemotes[name] = $0 }
        )
    }

    @ViewBuilder
    private func branchNodeRow(_ node: BranchTreeNode, localBranchCount: Int = 0) -> some View {
        switch node {
        case .leaf(let leaf):
            BranchRowView(
                branch: leaf.branch,
                displayName: leaf.displayName,
                canDelete: !leaf.branch.isCurrent && localBranchCount > 1,
                onCheckout: { Task { await vm?.requestCheckout(leaf.branch) } },
                onDelete: { Task { await vm?.requestDeleteBranch(leaf.branch) } }
            )
                .contentShape(Rectangle())
                .onTapGesture { vm?.selectCommit(bySha: leaf.branch.tipSha) }
        case .folder(let folderName, let children):
            DisclosureGroup {
                ForEach(children) { leaf in
                    BranchRowView(
                        branch: leaf.branch,
                        displayName: leaf.displayName,
                        canDelete: !leaf.branch.isCurrent && localBranchCount > 1,
                        onCheckout: { Task { await vm?.requestCheckout(leaf.branch) } },
                        onDelete: { Task { await vm?.requestDeleteBranch(leaf.branch) } }
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { vm?.selectCommit(bySha: leaf.branch.tipSha) }
                }
            } label: {
                Label(folderName, systemImage: "folder")
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let allTags = vm?.tags ?? []
        if !allTags.isEmpty {
            DisclosureGroup(isExpanded: $isTagsExpanded) {
                ForEach(allTags) { tag in
                    Label(tag.name, systemImage: "tag")
                        .font(.callout)
                        .contentShape(Rectangle())
                        .onTapGesture { vm?.selectCommit(bySha: tag.targetSha) }
                        .contextMenu {
                            Button {
                                ClipboardService.copy(tag.name)
                            } label: {
                                Label("Tag-Namen kopieren", systemImage: "doc.on.doc")
                            }
                        }
                }
            } label: {
                Label("Tags", systemImage: "tag")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    // MARK: - Commit-Bereich (Sync-Leiste + Liste)

    @ViewBuilder
    private var commitPane: some View {
        VStack(spacing: 0) {
            // Auto-Refresh-Banner: erscheint wenn neue Commits erkannt wurden
            if let news = appModel.newCommitStatus[repository.id], news.hasNews {
                autoRefreshBanner(news: news)
                Divider()
            }
            if let vm {
                syncBar(vm: vm)
                Divider()
                searchBar(vm: vm)
                if showAdvancedFilter {
                    advancedFilterBar(vm: vm)
                }
                Divider()
            }
            commitHistory
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func autoRefreshBanner(news: RepoNewCommits) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.callout)

            Text(news.summary.isEmpty ? "Neue Commits vorhanden" : news.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Aktualisieren") {
                Task {
                    await vm?.load()
                    await appModel.markRepositorySeen(repository.id)
                }
            }
            .controlSize(.small)
            .disabled(vm?.isLoading ?? true)
            .help("Commit-Liste lokal neu laden (kein Download)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.07))
    }

    @ViewBuilder
    private func syncBar(vm: RepositoryViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await vm.fetch() }
            } label: {
                Label("Vom Server prüfen", systemImage: "arrow.down.circle")
            }
            .disabled(!vm.hasRemote || vm.isFetching || vm.isPulling || vm.isLoading)
            .help("Holt den aktuellen Stand vom Server (git fetch)")

            if vm.isFetching || vm.isPulling {
                ProgressView().controlSize(.small)
            }

            syncStatus(vm: vm)

            Spacer()

            Button {
                Task { await vm.pull() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.triangle.pull")
            }
            .disabled(!vm.hasUpstream || vm.behindCount == 0 || vm.isFetching || vm.isPulling || vm.isLoading)
            .help("Übernimmt die Server-Commits per Fast-Forward; bei lokalen Abweichungen wird nach Bestätigung hart auf den Server-Stand zurückgesetzt")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Suchleiste

    @ViewBuilder
    private func searchBar(vm: RepositoryViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)

            TextField("Commits durchsuchen…", text: $criteria.message)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: criteria) { _, new in vm.updateSearch(new) }

            if vm.isSearching {
                ProgressView().controlSize(.mini)
            }

            // Erweiterte Filter umschalten
            Toggle(isOn: $showAdvancedFilter) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .foregroundStyle(showAdvancedFilter ? Color.accentColor : Color.secondary)
            .help("Erweiterte Filter (Autor, Datum, SHA)")

            // Löschen-Button bei aktiver Suche
            if criteria.isActive {
                Button {
                    criteria = CommitSearchCriteria()
                    vm.updateSearch(criteria)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Suche zurücksetzen")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func advancedFilterBar(vm: RepositoryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Autor
                HStack(spacing: 4) {
                    Text("Autor:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Name oder E-Mail", text: $criteria.author)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 160)
                        .onChange(of: criteria) { _, new in vm.updateSearch(new) }
                }

                // SHA
                HStack(spacing: 4) {
                    Text("SHA:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Präfix", text: $criteria.sha)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 100)
                        .onChange(of: criteria) { _, new in vm.updateSearch(new) }
                }
            }

            HStack(spacing: 12) {
                // Von-Datum
                HStack(spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { criteria.since != nil },
                        set: { active in
                            criteria.since = active ? Calendar.current.date(
                                byAdding: .month, value: -1, to: Date()) : nil
                            vm.updateSearch(criteria)
                        }
                    )) {
                        Text("Von:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    if let since = criteria.since {
                        DatePicker("", selection: Binding(
                            get: { since },
                            set: { criteria.since = $0; vm.updateSearch(criteria) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .font(.caption)
                    }
                }

                // Bis-Datum
                HStack(spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { criteria.until != nil },
                        set: { active in
                            criteria.until = active ? Date() : nil
                            vm.updateSearch(criteria)
                        }
                    )) {
                        Text("Bis:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    if let until = criteria.until {
                        DatePicker("", selection: Binding(
                            get: { until },
                            set: { criteria.until = $0; vm.updateSearch(criteria) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func syncStatus(vm: RepositoryViewModel) -> some View {
        if let message = vm.remoteStatusMessage {
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if vm.hasIndexLockConflict {
                    Button("Sperre aufheben") {
                        Task { await vm.removeIndexLock() }
                    }
                    .controlSize(.small)
                    .help("Löscht die verwaiste .git/index.lock, sofern kein Git-Prozess sie gerade verwendet.")
                }
            }
        } else if !vm.hasRemote {
            Text("Kein Remote")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !vm.hasUpstream {
            Text("Kein Upstream")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if vm.behindCount > 0 {
            HStack(spacing: 6) {
                Text("\(commitCountLabel(vm.behindCount)) auf dem Server")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                if vm.aheadCount > 0 {
                    Text("\(vm.aheadCount) voraus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 6) {
                Label("Aktuell", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vm.aheadCount > 0 {
                    Text("· \(vm.aheadCount) voraus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commitCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Commit" : "\(count) Commits"
    }

    // MARK: - Commit-Liste

    private var commitHistory: some View {
        VStack(spacing: 0) {
            if let vm, !vm.brokenRefs.isEmpty {
                brokenRefsBanner(vm.brokenRefs)
            }
            commitHistoryContent
        }
    }

    private func brokenRefsBanner(_ refs: [String]) -> some View {
        Label {
            Text("Kaputte Refs werden ignoriert: \(refs.joined(separator: ", ")). Die zugehörigen Dateien in .git/refs können gelöscht werden.")
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }

    @ViewBuilder
    private var commitHistoryContent: some View {
        if let vm {
            if vm.isLoading {
                ProgressView("Wird geladen…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                ContentUnavailableView(
                    "Fehler beim Laden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.isSearchActive && vm.searchResults.isEmpty && !vm.isSearching {
                ContentUnavailableView(
                    "Keine Treffer",
                    systemImage: "magnifyingglass",
                    description: Text("Keine Commits gefunden, die den Suchkriterien entsprechen.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.isSearchActive && vm.commits.isEmpty {
                ContentUnavailableView(
                    "Keine Commits",
                    systemImage: "tray",
                    description: Text("Dieses Repository enthält noch keine Commits.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                commitList(vm: vm)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Höhere Zeilen geben Luft zwischen Commits; spacing: 0 hält die
    // Graph-Linien lückenlos verbunden (kein Gap zwischen Zeilen).
    private static let rowHeight: CGFloat = 56
    private static let rowSpacing: CGFloat = 0

    private func commitList(vm: RepositoryViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    // Hinweis beim Sprung zu einem (noch) nicht geladenen Commit
                    if let msg = vm.branchJumpMessage {
                        HStack(spacing: 6) {
                            if vm.isRevealingCommit {
                                ProgressView().controlSize(.mini)
                            }
                            Text(msg)
                        }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                    }
                    ForEach(vm.visibleGraphRows, id: \.commit.id) { row in
                        let isSelected = vm.selectedCommitID == row.commit.id
                        HStack(spacing: 0) {
                            // GRAPH-SPALTE: feste (ziehbare) Breite, Graph wird rechts
                            // abgeschnitten wenn er breiter als die Spalte ist.
                            // Der Trenner daneben lässt sich ziehen, um mehr Lanes sichtbar
                            // zu machen.
                            CommitGraphView(row: row, rowHeight: Self.rowHeight)
                                .frame(width: graphColumnWidth, height: Self.rowHeight,
                                       alignment: .leading)
                                .clipped()

                            // ZIEHBARER TRENNER
                            graphColumnDivider

                            // BESCHREIBUNGS-SPALTE: füllt den restlichen Platz
                            CommitRowView(commit: row.commit)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                        .frame(height: Self.rowHeight)
                        .background(
                            isSelected
                                ? Color(nsColor: .selectedContentBackgroundColor)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { vm.selectedCommitID = row.commit.id }
                        .id(row.commit.id)
                    }

                    // Lazy-Loading-Indikator: erscheint erst wenn das Listenende
                    // sichtbar wird (LazyVStack rendert nur sichtbare Kinder).
                    // .onAppear löst die nächste Batch aus → echtes Infinite Scrolling.
                    if vm.visibleCanLoadMore {
                        HStack {
                            Spacer()
                            if vm.isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                // Unsichtbarer Trigger: onAppear feuert sobald diese
                                // Zeile in den sichtbaren Bereich scrollt.
                                Color.clear.frame(height: 1)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .onAppear { Task { await vm.loadMore() } }
                    }
                }
            }
            // Scroll wird am Token ausgelöst, nicht an der ID — dadurch funktioniert
            // der Sprung auch wenn der Commit bereits ausgewählt war (z.B. origin/main
            // zeigt auf denselben Commit wie main, kein ID-Wechsel nötig).
            .frame(maxWidth: .infinity)
            .onChange(of: vm.scrollRequestToken) { _, _ in
                if let id = vm.scrollTargetID {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Schmaler ziehbarer Balken zwischen Graph- und Beschreibungs-Spalte.
    /// Da er in jeder Zeile erscheint und alle denselben `graphColumnWidth`-State
    /// teilen, wirkt er wie eine einzige durchgehende Trennlinie.
    private var graphColumnDivider: some View {
        Color.clear
            .frame(width: 7, height: Self.rowHeight)
            // Sichtbare 1pt-Linie in der Mitte des 7pt-Trefferbereichs
            .overlay(Color.secondary.opacity(0.25).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = graphColumnWidthAtDragStart + value.translation.width
                        graphColumnWidth = min(max(proposed, 60), 600)
                    }
                    .onEnded { _ in
                        graphColumnWidthAtDragStart = graphColumnWidth
                    }
            )
    }

    // MARK: - Detail / Diff

    private var fileHistorySheet: some View {
        FileHistoryView(
            filePath: vm?.fileHistoryPath,
            commitShortSha: vm?.selectedCommit?.shortSha,
            entries: vm?.fileHistoryEntries ?? [],
            isLoading: vm?.isFileHistoryLoading ?? false,
            canLoadMore: vm?.fileHistoryCanLoadMore ?? false,
            error: vm?.fileHistoryError,
            diff: vm?.fileHistoryDiff,
            isDiffLoading: vm?.isFileHistoryDiffLoading ?? false,
            selectedSha: Binding(
                get: { vm?.selectedFileHistorySha },
                set: { vm?.selectedFileHistorySha = $0 }
            ),
            onSelectCommit: { sha in vm?.jumpToCommitFromFileHistory(sha: sha) },
            onLoadMore: { Task { await vm?.loadMoreFileHistory() } }
        )
    }

    @ViewBuilder
    private var commitDetail: some View {
        if let commit = vm?.selectedCommit {
            DiffView(
                commit: commit,
                diff: vm?.currentDiff,
                isLoading: vm?.isDiffLoading ?? false,
                onBlameRequest: { path in vm?.requestBlame(path: path) },
                onRevealInFinder: { path in
                    NSWorkspace.shared.selectFile(
                        repository.path.appendingPathComponent(path).path,
                        inFileViewerRootedAtPath: repository.path.path
                    )
                },
                onFileHistoryRequest: { path in vm?.requestFileHistory(path: path) }
            )
            // Ein Sprung zu einem weit hinten liegenden Commit setzt eine aktive Suche
            // zurück → das Suchfeld nachziehen.
            .onChange(of: vm?.searchCriteria) { _, new in
                if let new, new != criteria { criteria = new }
            }
            .sheet(isPresented: Binding(
                get: { vm?.showFileHistorySheet == true && vm?.fileHistoryPresentedFromBlame == false },
                set: { vm?.showFileHistorySheet = $0 }
            )) {
                fileHistorySheet
            }
            .sheet(isPresented: Binding(
                get: { vm?.showBlameSheet ?? false },
                set: { vm?.showBlameSheet = $0 }
            )) {
                BlameView(
                    filePath: vm?.blameFilePath,
                    commitShortSha: vm?.selectedCommit?.shortSha,
                    lines: vm?.blameLines ?? [],
                    isLoading: vm?.isBlameLoading ?? false,
                    error: vm?.blameError,
                    onSelectCommit: { sha in
                        vm?.selectCommit(bySha: sha)
                        vm?.showBlameSheet = false
                    },
                    onShowFileHistory: {
                        if let path = vm?.blameFilePath {
                            vm?.requestFileHistory(path: path, fromBlame: true)
                        }
                    }
                )
                // Verschachteltes Sheet: ein Wechsel zwischen zwei Sheets derselben
                // Ebene ist auf macOS unzuverlässig.
                .sheet(isPresented: Binding(
                    get: { vm?.showFileHistorySheet == true && vm?.fileHistoryPresentedFromBlame == true },
                    set: { vm?.showFileHistorySheet = $0 }
                )) {
                    fileHistorySheet
                }
            }
        } else {
            ContentUnavailableView(
                "Kein Commit ausgewählt",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Wähle einen Commit, um Details und Diff anzuzeigen.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Branch-Zeile

private struct BranchRowView: View {
    let branch: Branch
    let displayName: String
    var canDelete: Bool = false
    var onCheckout: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isCurrent ? "arrow.right.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : Color.secondary)
                .font(.callout)
            Text(displayName)
                .font(.callout)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
            Spacer()
            // Ahead/Behind-Badge: nur bei lokalem Branch mit Upstream und Abweichung
            if branch.upstreamName != nil {
                let a = branch.ahead ?? 0
                let b = branch.behind ?? 0
                if a > 0 || b > 0 {
                    HStack(spacing: 3) {
                        if a > 0 {
                            Label("\(a)", systemImage: "arrow.up")
                                .labelStyle(.titleAndIcon)
                        }
                        if b > 0 {
                            Label("\(b)", systemImage: "arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Upstream: \(branch.upstreamName!) · \(a) voraus, \(b) hinterher")
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(branch.tipSha.prefix(7)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if let date = branch.lastCommitDate {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Letzte Änderung: \(date.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .contextMenu {
            Button {
                ClipboardService.copy(branch.name)
            } label: {
                Label("Branch-Namen kopieren", systemImage: "doc.on.doc")
            }
            if !branch.isRemote && !branch.isCurrent {
                Button {
                    onCheckout?()
                } label: {
                    Label("Zu Branch wechseln", systemImage: "arrow.triangle.branch")
                }
            } else if branch.isRemote {
                Button {
                    onCheckout?()
                } label: {
                    Label("Lokalen Branch erstellen und auschecken", systemImage: "arrow.triangle.branch")
                }
            }
            if canDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Branch löschen", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Commit-Zeile

private struct CommitRowView: View {
    let commit: Commit

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !commit.refNames.isEmpty {
                refBadges
            }
            Text(commit.subject)
                .lineLimit(1)
                .font(.body)
            HStack(spacing: 8) {
                Text(commit.shortSha)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(commit.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.dateFormatter.string(from: commit.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button {
                ClipboardService.copy(commit.sha)
            } label: {
                Label("SHA kopieren", systemImage: "doc.on.doc")
            }
            Button {
                ClipboardService.copy(commit.subject)
            } label: {
                Label("Commit-Nachricht kopieren", systemImage: "doc.on.doc")
            }
        }
    }

    private var refBadges: some View {
        HStack(spacing: 4) {
            ForEach(commit.refNames, id: \.self) { ref in
                Text(ref)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeColor(for: ref).opacity(0.15))
                    .foregroundStyle(badgeColor(for: ref))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func badgeColor(for ref: String) -> Color {
        if ref.hasPrefix("HEAD") { return .orange }
        if ref.hasPrefix("tag:") { return .purple }
        if ref.hasPrefix("origin/") { return .green }
        return .blue
    }
}

#Preview {
    MainWindowView(
        repository: RepositoryBookmark(
            name: "Git-Client",
            path: URL(fileURLWithPath: "/Users/Tobias.Florian/Documents/Softwareentwicklung/Swift/Git-Client")
        )
    )
    .environment(AppModel())
}
