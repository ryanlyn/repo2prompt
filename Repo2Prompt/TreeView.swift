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

    private let policyURL = URL(string: "https://github.com/ryanlyn/Repo2Prompt/blob/main/PRIVACY_POLICY.md")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Repo2Prompt processes folders you explicitly choose on your Mac to generate a copyable prompt. Everything happens locally on your device.")

                    Text("Summary")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("- Repository contents are read locally, on-device.")
                        Text("- No accounts, no analytics, no data transmission.")
                        Text("- Recent folders and bookmarks are stored locally so you can reopen folders you picked.")
                        Text("- Copying a prompt happens only when you press Copy Prompt.")
                    }

                    Divider()

                    Text("The full privacy policy is maintained on GitHub:")
                    Link(destination: policyURL) {
                        Text(policyURL.absoluteString)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button("Open Privacy Policy") {
                        NSWorkspace.shared.open(policyURL)
                    }
                }
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

            HStack(spacing: 4) {
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
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    onToggleExpansion(node)
                } else {
                    onToggleSelection(node)
                }
            }
        }
        .opacity(rowOpacity)
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
        case "go", "rs", "kt", "java", "rb", "php", "dart", "lua":
            return "curlybraces"
        case "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css", "scss":
            return "chevron.left.forwardslash.chevron.right"
        case "sh": return "terminal"
        case "sql": return "cylinder"
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

            if node.isDirectory && node.isExpanded {
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
