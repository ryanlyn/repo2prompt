import Foundation

enum FolderScanner {
    private enum LeafKind {
        case file
        case ignoredDirectory
    }

    nonisolated private static let excludedNames: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", "Pods", ".DS_Store", "dist",
        ".next", ".nuxt", ".svn", ".hg", ".tox"
    ]

    nonisolated private static let excludedExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "ico", "svg", "webp",
        "mp3", "mp4", "wav", "avi", "mov",
        "mkv", "webm", "m4a", "flac",
        "heic", "bmp", "tiff", "psd", "sketch", "fig",
        "zip", "tar", "gz", "rar", "7z",
        "exe", "dll", "so", "dylib", "o",
        "bin", "class", "jar", "pyc", "pyo",
        "woff", "woff2", "ttf", "otf", "eot",
        "xcframework", "framework",
        "pdf", "doc", "docx", "xls", "xlsx"
    ]

    nonisolated private static let contentReadConcurrency = 8
    nonisolated private static let binaryDetectionByteCount = 8 * 1024

    // MARK: - Primary Scan

    static func scan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws -> FileNode {
        let materialized = try await loadDirectory(
            absolutePath: directory.path,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            applyIgnoreFilters: true
        )

        let rootName = directory.lastPathComponent
        let root = FileNode(
            name: rootName,
            relativePath: "",
            absolutePath: directory.path,
            isDirectory: true
        )

        for path in materialized.filePaths {
            insertPath(
                path,
                into: root,
                baseDirectory: directory,
                leafKind: .file,
                relativePathPrefix: "",
                selectedByDefault: true,
                expandedByDefault: false,
                modificationDates: materialized.modificationDates
            )
        }

        for path in materialized.ignoredDirectoryPaths {
            insertPath(
                path,
                into: root,
                baseDirectory: directory,
                leafKind: .ignoredDirectory,
                relativePathPrefix: "",
                selectedByDefault: true,
                expandedByDefault: false,
                modificationDates: materialized.modificationDates
            )
        }

        applyContents(materialized.contents, to: root)
        return root
    }

    static func materializeIgnoredDirectory(
        _ node: FileNode,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws {
        guard node.isDirectory, node.needsLazyLoad else { return }
        let absolutePath = node.absolutePath
        let relativePathPrefix = node.relativePath
        let selectedByDefault = node.isSelected

        let materialized = try await loadDirectory(
            absolutePath: absolutePath,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            applyIgnoreFilters: false
        )

        let directory = URL(fileURLWithPath: absolutePath)

        node.children.removeAll(keepingCapacity: true)

        for path in materialized.filePaths {
            insertPath(
                path,
                into: node,
                baseDirectory: directory,
                leafKind: .file,
                relativePathPrefix: relativePathPrefix,
                selectedByDefault: selectedByDefault,
                expandedByDefault: false,
                modificationDates: materialized.modificationDates
            )
        }

        applyContents(materialized.contents, to: node)
        node.needsLazyLoad = false
    }

    private struct MaterializedDirectory: Sendable {
        let filePaths: [String]
        let ignoredDirectoryPaths: [String]
        let modificationDates: [String: Date]
        let contents: [String: String]
    }

    nonisolated private static func loadDirectory(
        absolutePath: String,
        showHiddenFiles: Bool,
        followSymlinks: Bool,
        applyIgnoreFilters: Bool
    ) async throws -> MaterializedDirectory {
        let directory = URL(fileURLWithPath: absolutePath)
        let scanResult = try manualScan(
            directory: directory,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            applyIgnoreFilters: applyIgnoreFilters
        )

        let datePaths = scanResult.filePaths + scanResult.ignoredDirectoryPaths
        let dates = modificationDates(forRelativePaths: datePaths, baseDirectory: directory)
        let absolutePaths = scanResult.filePaths.map { directory.appendingPathComponent($0).path }
        let contents = await readContents(absolutePaths: absolutePaths)

        return MaterializedDirectory(
            filePaths: scanResult.filePaths,
            ignoredDirectoryPaths: scanResult.ignoredDirectoryPaths,
            modificationDates: dates,
            contents: contents
        )
    }

    // MARK: - Content Loading

    private static func applyContents(_ contents: [String: String], to node: FileNode) {
        if node.isDirectory {
            for child in node.children {
                applyContents(contents, to: child)
            }
        } else if let content = contents[node.absolutePath] {
            node.content = content
            node.tokenCount = ScanSettings.estimateTokens(content)
        }
    }

    nonisolated private static func readContents(absolutePaths: [String]) async -> [String: String] {
        guard !absolutePaths.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, String?).self) { group in
            var results: [String: String] = [:]
            var index = 0
            let limit = min(contentReadConcurrency, absolutePaths.count)

            while index < limit {
                let path = absolutePaths[index]
                group.addTask { (path, readTextFile(atPath: path)) }
                index += 1
            }

            while let (path, content) = await group.next() {
                if let content {
                    results[path] = content
                }
                if index < absolutePaths.count {
                    let next = absolutePaths[index]
                    group.addTask { (next, readTextFile(atPath: next)) }
                    index += 1
                }
            }

            return results
        }
    }

    nonisolated private static func readTextFile(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let head: Data
        do {
            head = try handle.read(upToCount: binaryDetectionByteCount) ?? Data()
        } catch {
            return nil
        }

        if head.contains(0) { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - File Discovery

    private struct ScanResult {
        var filePaths: [String]
        var ignoredDirectoryPaths: [String]
    }

    nonisolated private static func manualScan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool,
        applyIgnoreFilters: Bool
    ) throws -> ScanResult {
        var result = ScanResult(filePaths: [], ignoredDirectoryPaths: [])
        var stack = GitIgnoreStack()
        try walk(
            directory: directory,
            relativePath: "",
            stack: &stack,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            applyIgnoreFilters: applyIgnoreFilters,
            into: &result
        )
        result.filePaths.sort()
        result.ignoredDirectoryPaths.sort()
        return result
    }

    nonisolated private static func walk(
        directory: URL,
        relativePath: String,
        stack: inout GitIgnoreStack,
        showHiddenFiles: Bool,
        followSymlinks: Bool,
        applyIgnoreFilters: Bool,
        into result: inout ScanResult
    ) throws {
        let fm = FileManager.default

        var pushed = false
        if applyIgnoreFilters {
            let gitignoreURL = directory.appendingPathComponent(".gitignore")
            if fm.fileExists(atPath: gitignoreURL.path),
               let contents = try? String(contentsOf: gitignoreURL, encoding: .utf8) {
                let matcher = GitIgnoreParser.parse(contents: contents, base: relativePath)
                if !matcher.rules.isEmpty {
                    stack.push(matcher)
                    pushed = true
                }
            }
        }
        defer { if pushed { stack.pop() } }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey
        ]

        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
        } catch {
            return
        }

        for child in children {
            let name = child.lastPathComponent
            if !showHiddenFiles && name.hasPrefix(".") { continue }

            let childRelative = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
            let vals = try? child.resourceValues(forKeys: keys)

            if !followSymlinks && vals?.isSymbolicLink == true { continue }

            if vals?.isDirectory == true {
                if applyIgnoreFilters && excludedNames.contains(name) {
                    continue
                }
                if applyIgnoreFilters,
                   stack.isIgnored(relativePath: childRelative, isDirectory: true) {
                    result.ignoredDirectoryPaths.append(childRelative)
                    continue
                }
                try walk(
                    directory: child,
                    relativePath: childRelative,
                    stack: &stack,
                    showHiddenFiles: showHiddenFiles,
                    followSymlinks: followSymlinks,
                    applyIgnoreFilters: applyIgnoreFilters,
                    into: &result
                )
            } else if vals?.isRegularFile == true {
                if excludedExts.contains(child.pathExtension.lowercased()) { continue }
                if applyIgnoreFilters,
                   stack.isIgnored(relativePath: childRelative, isDirectory: false) {
                    continue
                }
                result.filePaths.append(childRelative)
            }
        }
    }

    // MARK: - Helpers

    nonisolated private static func modificationDate(atPath path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    nonisolated private static func modificationDates(
        forRelativePaths paths: [String],
        baseDirectory: URL
    ) -> [String: Date] {
        var result: [String: Date] = [:]
        for path in paths {
            let parts = path.split(separator: "/")
            for index in 0..<parts.count {
                let subtree = parts[0...index].joined(separator: "/")
                if result[subtree] != nil { continue }
                let absolute = baseDirectory.appendingPathComponent(subtree).path
                if let date = modificationDate(atPath: absolute) {
                    result[subtree] = date
                }
            }
        }
        return result
    }

    private static func insertPath(
        _ path: String,
        into root: FileNode,
        baseDirectory: URL,
        leafKind: LeafKind,
        relativePathPrefix: String,
        selectedByDefault: Bool,
        expandedByDefault: Bool,
        modificationDates: [String: Date]
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
            let absolutePath = baseDirectory.appendingPathComponent(subtreePath).path
            let node = FileNode(
                name: part,
                relativePath: relativePath,
                absolutePath: absolutePath,
                isDirectory: !isLeaf || leafKind == .ignoredDirectory,
                modificationDate: modificationDates[subtreePath],
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
}
