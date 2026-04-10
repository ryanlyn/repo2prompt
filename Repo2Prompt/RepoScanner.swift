import Foundation

enum RepoScanner {
    private struct ScanPaths {
        let filePaths: [String]
        let ignoredDirectoryPaths: [String]
    }

    private enum LeafKind {
        case file
        case ignoredDirectory
    }

    private static let excludedNames: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", "Pods", ".DS_Store", "dist",
        ".next", ".nuxt", ".svn", ".hg", ".tox"
    ]

    private static let excludedExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "ico", "svg", "webp",
        "mp3", "mp4", "wav", "avi", "mov",
        "zip", "tar", "gz", "rar", "7z",
        "exe", "dll", "so", "dylib", "o",
        "pdf", "doc", "docx", "xls", "xlsx"
    ]

    // MARK: - Primary Scan

    static func scan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws -> FileNode {
        let scanPaths = try await getScanPaths(
            in: directory,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks
        )

        let rootName = directory.lastPathComponent
        let root = FileNode(
            name: rootName,
            relativePath: "",
            absolutePath: directory.path,
            isDirectory: true
        )

        for path in scanPaths.filePaths {
            insertPath(
                path,
                into: root,
                baseDirectory: directory,
                leafKind: .file,
                relativePathPrefix: "",
                selectedByDefault: true,
                expandedByDefault: false
            )
        }

        for path in scanPaths.ignoredDirectoryPaths {
            insertPath(
                path,
                into: root,
                baseDirectory: directory,
                leafKind: .ignoredDirectory,
                relativePathPrefix: "",
                selectedByDefault: false,
                expandedByDefault: false
            )
        }

        loadContents(node: root)
        return root
    }

    static func materializeIgnoredDirectory(
        _ node: FileNode,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws {
        guard node.isDirectory, node.needsLazyLoad else { return }

        let directory = URL(fileURLWithPath: node.absolutePath)
        let filePaths = try manualScan(
            directory: directory,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            useBuiltInExclusions: false
        )

        node.children.removeAll(keepingCapacity: true)

        for path in filePaths {
            insertPath(
                path,
                into: node,
                baseDirectory: directory,
                leafKind: .file,
                relativePathPrefix: node.relativePath,
                selectedByDefault: node.isSelected,
                expandedByDefault: false
            )
        }

        loadContents(node: node)
        node.needsLazyLoad = false
    }

    // MARK: - Git Diff

    static func gitDiff(in directory: URL) -> String? {
        do {
            guard let data = try runGit(arguments: ["diff", "HEAD"], in: directory) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Content Loading

    private static func loadContents(node: FileNode) {
        if node.isDirectory {
            for child in node.children {
                loadContents(node: child)
            }
        } else {
            let url = URL(fileURLWithPath: node.absolutePath)
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8),
                  !content.contains("\0") else { return }
            node.content = content
            node.tokenCount = ScanSettings.estimateTokens(content)
        }
    }

    // MARK: - File Discovery

    private static func getScanPaths(
        in directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws -> ScanPaths {
        if let gitFiles = try gitLsFiles(in: directory, showHiddenFiles: showHiddenFiles) {
            return ScanPaths(
                filePaths: gitFiles,
                ignoredDirectoryPaths: try gitIgnoredDirectories(
                    in: directory,
                    showHiddenFiles: showHiddenFiles
                )
            )
        }
        return ScanPaths(
            filePaths: try manualScan(
                directory: directory,
                showHiddenFiles: showHiddenFiles,
                followSymlinks: followSymlinks,
                useBuiltInExclusions: true
            ),
            ignoredDirectoryPaths: []
        )
    }

    private static func gitLsFiles(in directory: URL, showHiddenFiles: Bool) throws -> [String]? {
        guard let data = try runGit(
            arguments: ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            in: directory
        ) else {
            return nil
        }

        var paths = parseNullSeparatedPaths(from: data)

        if !showHiddenFiles {
            paths = paths.filter { path in
                !path.split(separator: "/").contains { $0.hasPrefix(".") }
            }
        }

        return paths.sorted()
    }

    private static func gitIgnoredDirectories(in directory: URL, showHiddenFiles: Bool) throws -> [String] {
        guard let data = try runGit(
            arguments: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"],
            in: directory
        ) else {
            return []
        }

        var paths = parseNullSeparatedPaths(from: data)
            .filter { $0.hasSuffix("/") }
            .map { String($0.dropLast()) }

        if !showHiddenFiles {
            paths = paths.filter { path in
                !path.split(separator: "/").contains { $0.hasPrefix(".") }
            }
        }

        return Array(Set(paths)).sorted()
    }

    private static func manualScan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool,
        useBuiltInExclusions: Bool
    ) throws -> [String] {
        var results: [String] = []
        let fm = FileManager.default

        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        var keys: [URLResourceKey] = [.isRegularFileKey]
        if !followSymlinks {
            keys.append(.isSymbolicLinkKey)
        }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: options
        ) else { return [] }

        let base = directory.path + "/"

        while let url = enumerator.nextObject() as? URL {
            if useBuiltInExclusions, excludedNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let vals = try? url.resourceValues(forKeys: Set(keys))

            if !followSymlinks, vals?.isSymbolicLink == true {
                continue
            }

            guard vals?.isRegularFile == true else { continue }
            if excludedExts.contains(url.pathExtension.lowercased()) { continue }

            results.append(String(url.path.dropFirst(base.count)))
        }
        return results.sorted()
    }

    // MARK: - Helpers

    private static func modificationDate(atPath path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    private static func insertPath(
        _ path: String,
        into root: FileNode,
        baseDirectory: URL,
        leafKind: LeafKind,
        relativePathPrefix: String,
        selectedByDefault: Bool,
        expandedByDefault: Bool
    ) {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return }

        var current = root

        for (index, part) in parts.enumerated() {
            let isLeaf = index == parts.count - 1
            let subtreePath = parts[0...index].joined(separator: "/")
            let relativePath = relativePathPrefix.isEmpty ? subtreePath : "\(relativePathPrefix)/\(subtreePath)"

            if let existing = current.children.first(where: { $0.name == part }) {
                current = existing
                continue
            }

            let isIgnoredDirectory = isLeaf && leafKind == .ignoredDirectory
            let node = FileNode(
                name: part,
                relativePath: relativePath,
                absolutePath: baseDirectory.appendingPathComponent(subtreePath).path,
                isDirectory: !isLeaf || leafKind == .ignoredDirectory,
                modificationDate: modificationDate(atPath: baseDirectory.appendingPathComponent(subtreePath).path),
                isGitIgnored: isIgnoredDirectory,
                isSelected: isIgnoredDirectory ? false : selectedByDefault,
                isExpanded: isIgnoredDirectory ? false : expandedByDefault,
                needsLazyLoad: isIgnoredDirectory
            )
            node.parent = current
            current.children.append(node)
            current = node
        }
    }

    private static func runGit(arguments: [String], in directory: URL) throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    private static func parseNullSeparatedPaths(from data: Data) -> [String] {
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\0").map(String.init)
    }
}
