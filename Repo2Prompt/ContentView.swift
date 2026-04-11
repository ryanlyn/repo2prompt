import SwiftUI

// MARK: - Recent Directory Model

struct RecentDirectory: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    var name: String
    var bookmarkData: Data?
    var isStarred: Bool = false
    var lastAccessed: Date = Date()
}

// MARK: - Content View

struct ContentView: View {
    private enum Constants {
        static let recentDirectoriesKey = "recentDirectories"
        static let maximumRecents = 20
    }

    fileprivate struct PreviewState {
        let selectedURL: URL?
        let rootNode: FileNode?
        let settings: ScanSettings
        let recents: [RecentDirectory]
    }

    @State private var selectedURL: URL?
    @State private var rootNode: FileNode?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var showSettings = true
    @State private var settings = ScanSettings()
    @State private var recents: [RecentDirectory] = []
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var currentScanTask: Task<Void, Never>?

    private var isRunningInPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    private var starredRecents: [RecentDirectory] {
        sortedRecents.filter(\.isStarred)
    }

    private var unstarredRecents: [RecentDirectory] {
        sortedRecents.filter { !$0.isStarred }
    }

    init() {
        _selectedURL = State(initialValue: nil)
        _rootNode = State(initialValue: nil)
        _isScanning = State(initialValue: false)
        _errorMessage = State(initialValue: nil)
        _copied = State(initialValue: false)
        _showSettings = State(initialValue: true)
        _settings = State(initialValue: ScanSettings())
        _recents = State(initialValue: [])
        _sidebarVisibility = State(initialValue: .all)
    }

    fileprivate init(previewState: PreviewState) {
        _selectedURL = State(initialValue: previewState.selectedURL)
        _rootNode = State(initialValue: previewState.rootNode)
        _isScanning = State(initialValue: false)
        _errorMessage = State(initialValue: nil)
        _copied = State(initialValue: false)
        _showSettings = State(initialValue: true)
        _settings = State(initialValue: previewState.settings)
        _recents = State(initialValue: previewState.recents)
        _sidebarVisibility = State(initialValue: .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebarView()
        } detail: {
            detailView()
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            guard !isRunningInPreview else { return }
            loadRecents()
            #if DEBUG
            let cwd = FileManager.default.currentDirectoryPath
            let home = NSHomeDirectory()
            let hasGit = FileManager.default.fileExists(atPath: "\(cwd)/.git")
            let inDevDir = cwd.hasPrefix("\(home)/dev")
            if hasGit || inDevDir {
                let url = URL(fileURLWithPath: cwd)
                scan(url)
                addRecent(url)
            }
            #endif
        }
        .onChange(of: settings.includeGlob) { _, _ in applyFilters() }
        .onChange(of: settings.excludeGlob) { _, _ in applyFilters() }
        .onChange(of: settings.sortOrder) { _, _ in applySort() }
        .onReceive(NotificationCenter.default.publisher(for: .repo2PromptOpenFolder)) { _ in
            pickFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repo2PromptCopyPrompt)) { _ in
            guard rootNode != nil else { return }
            copyPrompt()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repo2PromptToggleSettings)) { _ in
            withAnimation { showSettings.toggle() }
        }
    }

    // MARK: - Sidebar

    private func sidebarView() -> some View {
        List {
            if !starredRecents.isEmpty {
                Section("Starred") {
                    ForEach(starredRecents) { recent in
                        recentRow(recent)
                    }
                }
            }

            Section("Recent") {
                ForEach(unstarredRecents) { recent in
                    recentRow(recent)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) {
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder...", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .padding()
        }
    }

    private func recentRow(_ recent: RecentDirectory) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            Text(recent.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                toggleStar(recent)
            } label: {
                Image(systemName: recent.isStarred ? "star.fill" : "star")
                    .foregroundStyle(recent.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openRecent(recent)
        }
        .contextMenu {
            Button(recent.isStarred ? "Unstar" : "Star") {
                toggleStar(recent)
            }
            Button("Remove from Recents", role: .destructive) {
                removeRecent(recent)
            }
        }
    }

    // MARK: - Detail

    private func detailView() -> some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsPanel(settings: settings, onRescanNeeded: { rescanSelectedFolder() })
                Divider()
            }

            if let rootNode {
                fileTree(rootNode)
            } else {
                ContentUnavailableView(
                    "No Folder Selected",
                    systemImage: "folder",
                    description: Text("Choose a folder from the sidebar or add one.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            copyPromptButton
        }
        .toolbar(content: detailToolbar)
    }

    @ToolbarContentBuilder
    private func detailToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
            }
            .help("Toggle settings")
        }

        ToolbarItem(placement: .automatic) {
            if isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if let rootNode {
                toolbarSummary(
                    fileCount: rootNode.selectedFileCount,
                    tokenCount: rootNode.effectiveTokenCount
                )
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private func toolbarSummary(fileCount: Int, tokenCount: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(fileCount) files")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text("~\(formatTokens(tokenCount)) tokens")
                .foregroundStyle(.orange)
                .font(.callout)
                .fontWeight(.semibold)
        }
    }

    private func fileTree(_ rootNode: FileNode) -> some View {
        ScrollView {
            FileTreeView(
                node: rootNode,
                totalTokens: rootNode.effectiveTokenCount,
                showTokenMap: settings.showTokenMap,
                onToggleSelection: toggleSelection,
                onToggleExpansion: toggleExpansion
            )
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Floating Actions

    @ViewBuilder
    private var copyPromptButton: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(in: .capsule)
            }

            Button {
                copyPrompt()
            } label: {
                Label(copied ? "Copied!" : "Copy Prompt",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 26))
            .disabled(rootNode == nil)
            .help(selectedURL?.lastPathComponent ?? "Copy prompt")
        }
        .padding(16)
    }

    // MARK: - Recents Persistence

    private var sortedRecents: [RecentDirectory] {
        recents.sorted { a, b in
            if a.isStarred != b.isStarred { return a.isStarred }
            return a.lastAccessed > b.lastAccessed
        }
    }

    private func addRecent(_ url: URL) {
        let path = url.path
        let name = url.lastPathComponent
        let bookmarkData = try? createBookmark(for: url)
        if let index = recents.firstIndex(where: { $0.path == path }) {
            recents[index].lastAccessed = Date()
            recents[index].name = name
            recents[index].bookmarkData = bookmarkData
        } else {
            recents.insert(
                RecentDirectory(path: path, name: name, bookmarkData: bookmarkData),
                at: 0
            )
            if recents.count > Constants.maximumRecents {
                recents = Array(recents.prefix(Constants.maximumRecents))
            }
        }
        saveRecents()
    }

    private func toggleStar(_ recent: RecentDirectory) {
        if let index = recents.firstIndex(where: { $0.path == recent.path }) {
            recents[index].isStarred.toggle()
            saveRecents()
        }
    }

    private func removeRecent(_ recent: RecentDirectory) {
        recents.removeAll { $0.path == recent.path }
        if selectedURL?.path == recent.path {
            selectedURL = nil
            rootNode = nil
        }
        saveRecents()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Constants.recentDirectoriesKey),
              let decoded = try? JSONDecoder().decode([RecentDirectory].self, from: data) else { return }
        recents = decoded
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: Constants.recentDirectoriesKey)
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    private func openRecent(_ recent: RecentDirectory) {
        if recent.bookmarkData == nil {
            reauthorizeRecent(recent)
            return
        }
        do {
            let url = try resolveRecentURL(for: recent)
            openFolder(url)
        } catch {
            reauthorizeRecent(recent)
        }
    }

    private func reauthorizeRecent(_ recent: RecentDirectory) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: recent.path)
        panel.message = "Re-grant access to \(recent.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    private func openFolder(_ url: URL) {
        errorMessage = nil
        addRecent(url)
        scan(url)
    }

    private func rescanSelectedFolder() {
        guard let selectedURL else { return }
        scan(selectedURL)
    }

    private func scan(_ url: URL) {
        currentScanTask?.cancel()

        selectedURL = url
        isScanning = true
        errorMessage = nil
        rootNode = nil
        copied = false

        var thisTask: Task<Void, Never>?
        let task = Task {
            defer {
                if currentScanTask == thisTask {
                    isScanning = false
                    currentScanTask = nil
                }
            }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let node = try await FolderScanner.scan(
                    directory: url,
                    showHiddenFiles: settings.showHiddenFiles,
                    followSymlinks: settings.followSymlinks
                )

                if Task.isCancelled { return }

                rootNode = node
                errorMessage = nil
                applyFilters()
                applySort()
            } catch {
                if Task.isCancelled { return }
                errorMessage = error.localizedDescription
            }
        }
        thisTask = task
        currentScanTask = task
    }

    private func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveRecentURL(for recent: RecentDirectory) throws -> URL {
        guard let bookmarkData = recent.bookmarkData else {
            return URL(fileURLWithPath: recent.path)
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale, let index = recents.firstIndex(where: { $0.path == recent.path }) {
            recents[index].bookmarkData = try? createBookmark(for: url)
            recents[index].lastAccessed = Date()
            saveRecents()
        }

        return url
    }

    private func applyFilters() {
        guard let rootNode else { return }
        applyFilters(to: rootNode)
    }

    private func applyFilters(to node: FileNode) {
        if node.isDirectory {
            for child in node.children {
                applyFilters(to: child)
            }
            node.isFilteredOut = node.needsLazyLoad ? false : node.children.allSatisfy { $0.isFilteredOut }
        } else {
            node.isFilteredOut = !settings.shouldIncludeFile(relativePath: node.relativePath)
        }
    }

    private func applySort() {
        rootNode?.sortChildren(by: settings.sortOrder)
    }

    private func copyPrompt() {
        guard let rootNode else { return }
        let prompt = settings.generatePrompt(root: rootNode)

        if prompt.count > 5 * 1024 * 1024 {
            let alert = NSAlert()
            alert.messageText = "Large prompt"
            alert.informativeText = "This prompt is \(prompt.count / 1024 / 1024) MB. Copy to clipboard anyway?"
            alert.addButton(withTitle: "Copy")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }

    private func toggleSelection(_ node: FileNode) {
        let shouldSelect = node.selectionState != .all

        guard shouldSelect, node.isDirectory, node.needsLazyLoad else {
            node.toggle()
            applyFilters()
            applySort()
            return
        }

        materializeIgnoredDirectory(node) {
            node.isSelected = true
            applyFilters()
            applySort()
        }
    }

    private func toggleExpansion(_ node: FileNode) {
        guard node.isDirectory else { return }

        guard node.needsLazyLoad, !node.isExpanded else {
            withAnimation(.easeInOut(duration: 0.15)) {
                node.isExpanded.toggle()
            }
            return
        }

        materializeIgnoredDirectory(node) {
            withAnimation(.easeInOut(duration: 0.15)) {
                node.isExpanded = true
            }
            applyFilters()
            applySort()
        }
    }

    private func materializeIgnoredDirectory(_ node: FileNode, completion: @escaping () -> Void) {
        guard !node.isLoadingChildren else { return }

        node.isLoadingChildren = true

        let scopedURL = selectedURL

        Task {
            let didStartAccessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStartAccessing {
                    scopedURL?.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try await FolderScanner.materializeIgnoredDirectory(
                    node,
                    showHiddenFiles: settings.showHiddenFiles,
                    followSymlinks: settings.followSymlinks
                )
                node.isLoadingChildren = false
                completion()
            } catch {
                node.isLoadingChildren = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    ContentView(previewState: ContentView.PreviewState.mock)
}
private extension ContentView.PreviewState {
    static var mock: Self {
        let selectedURL = URL(fileURLWithPath: "/Users/ryan/Projects/Repo2Prompt")
        let rootNode = makeRootNode(basePath: selectedURL.path)
        let settings = ScanSettings()
        settings.includeGlob = "*.swift, *.md"
        settings.excludeGlob = ".build, DerivedData, *.log"

        let recents = [
            RecentDirectory(path: "/Users/ryan/Projects/Data", name: "Data", isStarred: true),
            RecentDirectory(path: selectedURL.path, name: "Repo2Prompt")
        ]

        return Self(
            selectedURL: selectedURL,
            rootNode: rootNode,
            settings: settings,
            recents: recents
        )
    }

    static func makeRootNode(basePath: String) -> FileNode {
        let root = directory("Repo2Prompt", path: "", basePath: basePath)
        let sources = directory("Sources", path: "Sources", basePath: basePath)
        let views = directory("Views", path: "Sources/Views", basePath: basePath)
        let models = directory("Models", path: "Sources/Models", basePath: basePath)

        let contentView = file(
            "ContentView.swift",
            path: "Sources/Views/ContentView.swift",
            basePath: basePath,
            tokens: 188
        )
        let treeView = file(
            "TreeView.swift",
            path: "Sources/Views/TreeView.swift",
            basePath: basePath,
            tokens: 72
        )
        let scanner = file(
            "FolderScanner.swift",
            path: "Sources/Models/FolderScanner.swift",
            basePath: basePath,
            tokens: 116
        )
        let settings = file(
            "ScanSettings.swift",
            path: "Sources/Models/ScanSettings.swift",
            basePath: basePath,
            tokens: 94
        )
        let readme = file(
            "README.md",
            path: "README.md",
            basePath: basePath,
            tokens: 28
        )

        connect(parent: root, child: sources)
        connect(parent: sources, child: views)
        connect(parent: sources, child: models)
        connect(parent: views, child: contentView)
        connect(parent: views, child: treeView)
        connect(parent: models, child: scanner)
        connect(parent: models, child: settings)
        connect(parent: root, child: readme)

        root.sortChildren(by: .nameAsc)
        return root
    }

    static func connect(parent: FileNode, child: FileNode) {
        child.parent = parent
        parent.children.append(child)
    }

    static func directory(_ name: String, path: String, basePath: String) -> FileNode {
        FileNode(
            name: name,
            relativePath: path,
            absolutePath: basePath + (path.isEmpty ? "" : "/\(path)"),
            isDirectory: true
        )
    }

    static func file(_ name: String, path: String, basePath: String, tokens: Int) -> FileNode {
        let node = FileNode(
            name: name,
            relativePath: path,
            absolutePath: "\(basePath)/\(path)",
            isDirectory: false
        )
        node.content = "// Preview content"
        node.tokenCount = tokens
        return node
    }
}
