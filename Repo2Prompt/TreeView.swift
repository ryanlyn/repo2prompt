import SwiftUI

// MARK: - Settings Panel

struct SettingsPanel: View {
    @Bindable var settings: ScanSettings
    var onRescanNeeded: () -> Void
    @State private var showPrivacyPolicy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Glob filters
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include").font(.caption).foregroundStyle(.secondary)
                    TextField("*.swift, *.py", text: $settings.includeGlob)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exclude").font(.caption).foregroundStyle(.secondary)
                    TextField("*.lock, dist/**", text: $settings.excludeGlob)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            // Toggles row 1
            HStack(spacing: 16) {
                Toggle("Line numbers", isOn: $settings.showLineNumbers)
                Toggle("Git diff", isOn: $settings.includeGitDiff)
                Toggle("Absolute paths", isOn: $settings.useAbsolutePaths)
                Toggle("Full tree", isOn: $settings.fullDirectoryTree)
            }
            .toggleStyle(.checkbox)

            // Toggles row 2 + sort
            HStack(spacing: 16) {
                Toggle("Hidden files", isOn: $settings.showHiddenFiles)
                    .onChange(of: settings.showHiddenFiles) { _, _ in onRescanNeeded() }
                Toggle("Follow symlinks", isOn: $settings.followSymlinks)
                    .onChange(of: settings.followSymlinks) { _, _ in onRescanNeeded() }

                Spacer()

                Picker("Sort:", selection: $settings.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
            .toggleStyle(.checkbox)

            // Instruction
            VStack(alignment: .leading, spacing: 2) {
                Text("Instruction").font(.caption).foregroundStyle(.secondary)
                TextField("Optional instruction appended to prompt...", text: $settings.instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }

            HStack(spacing: 12) {
                Button("Privacy") {
                    showPrivacyPolicy = true
                }
                .buttonStyle(.plain)

                if let supportURL = URL(string: "https://github.com/ryanlyn/repo2prompt") {
                    Link("Support", destination: supportURL)
                        .buttonStyle(.plain)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicySheet()
        }
    }
}

private struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("""
                Repo2Prompt processes folders you explicitly choose on your Mac to generate a copyable prompt.

                Data use
                - Repository contents are read locally on-device.
                - Recent folders and security-scoped bookmarks are stored locally to reopen folders you picked.
                - The app does not create accounts, transmit analytics, or sell data.

                User control
                - You choose which folder to open.
                - You choose which files and folders remain selected.
                - Copying a prompt happens only when you press Copy Prompt.

                Storage
                - Preferences and recent-folder metadata are stored using standard Apple system storage.
                - Repository files are not uploaded by the app.

                Support
                Visit the project support page on GitHub for updates and contact details.
                """)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(20)
            }
            .navigationTitle("Privacy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {
    @Bindable var node: FileNode
    var totalTokens: Int
    var showTokenMap: Bool
    var onToggleSelection: (FileNode) -> Void
    var onToggleExpansion: (FileNode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if node.isDirectory {
                Button {
                    onToggleExpansion(node)
                } label: {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            Button {
                onToggleSelection(node)
            } label: {
                Image(systemName: checkboxImage)
                    .foregroundStyle(node.selectionState == .some ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 16)

            Text(node.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            if node.isGitIgnored {
                Text("gitignored")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if node.isLoadingChildren {
                ProgressView()
                    .controlSize(.small)
            }

            if showTokenSummary {
                Spacer()

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.orange.opacity(0.3))
                        .frame(width: geo.size.width * min(summaryFraction, 1.0))
                }
                .frame(width: 80, height: 12)

                Text(String(format: "%.1f%%", summaryFraction * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)

                Text(formatTokens(summaryTokenCount))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(width: 45, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
        .opacity(rowOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard node.isDirectory else { return }
            onToggleExpansion(node)
        }
    }

    private var checkboxImage: String {
        switch node.selectionState {
        case .all: return "checkmark.square.fill"
        case .some: return "minus.square.fill"
        case .none: return "square"
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        case "json", "yaml", "yml", "toml": return "gearshape"
        default: return "doc"
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private var showTokenSummary: Bool {
        guard showTokenMap, totalTokens > 0 else { return false }
        if node.isDirectory {
            return !node.isExpanded && summaryTokenCount > 0
        }
        return true
    }

    private var summaryTokenCount: Int {
        node.isDirectory ? node.effectiveTokenCount : node.tokenCount
    }

    private var summaryFraction: Double {
        Double(summaryTokenCount) / Double(max(totalTokens, 1))
    }

    private var rowOpacity: Double {
        if node.isFilteredOut { return 0.4 }
        if node.isGitIgnored && node.selectionState == .none { return 0.72 }
        return 1.0
    }
}

// MARK: - Recursive File Tree

struct FileTreeView: View {
    @Bindable var node: FileNode
    var totalTokens: Int
    var showTokenMap: Bool
    var depth: Int = 0
    var onToggleSelection: (FileNode) -> Void
    var onToggleExpansion: (FileNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if depth > 0 {
                FileTreeRow(
                    node: node,
                    totalTokens: totalTokens,
                    showTokenMap: showTokenMap,
                    onToggleSelection: onToggleSelection,
                    onToggleExpansion: onToggleExpansion
                )
                    .padding(.leading, CGFloat(depth - 1) * 20)
                    .padding(.vertical, 2)
            }

            if node.isDirectory && (node.isExpanded || depth == 0) {
                ForEach(node.children) { child in
                    if !child.isFilteredOut {
                        FileTreeView(
                            node: child,
                            totalTokens: totalTokens,
                            showTokenMap: showTokenMap,
                            depth: depth + 1,
                            onToggleSelection: onToggleSelection,
                            onToggleExpansion: onToggleExpansion
                        )
                    }
                }
            }
        }
    }
}
