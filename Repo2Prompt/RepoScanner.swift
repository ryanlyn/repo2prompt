import Foundation

enum RepoScanner {

    // MARK: - Primary Scan

    static func scan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws -> FileNode {
        let filePaths = try await getFilePaths(
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

        for path in filePaths {
            let parts = path.split(separator: "/").map(String.init)
            var current = root

            for (index, part) in parts.enumerated() {
                let isLeaf = index == parts.count - 1
                let partialPath = parts[0...index].joined(separator: "/")

                if let existing = current.children.first(where: { $0.name == part }) {
                    current = existing
                } else {
                    let fullPath = directory.appendingPathComponent(partialPath).path
                    let node = FileNode(
                        name: part,
                        relativePath: partialPath,
                        absolutePath: fullPath,
                        isDirectory: !isLeaf,
                        modificationDate: modificationDate(atPath: fullPath)
                    )
                    node.parent = current
                    current.children.append(node)
                    current = node
                }
            }
        }

        loadContents(node: root)
        return root
    }

    // MARK: - Git Diff

    static func gitDiff(in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "HEAD"]
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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

    private static func getFilePaths(
        in directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) async throws -> [String] {
        if let gitFiles = try gitLsFiles(in: directory, showHiddenFiles: showHiddenFiles) {
            return gitFiles
        }
        return try manualScan(
            directory: directory,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks
        )
    }

    private static func gitLsFiles(in directory: URL, showHiddenFiles: Bool) throws -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files", "--cached", "--others", "--exclude-standard"]
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var paths = output.split(separator: "\n").map(String.init)

        if !showHiddenFiles {
            paths = paths.filter { path in
                !path.split(separator: "/").contains { $0.hasPrefix(".") }
            }
        }

        return paths.sorted()
    }

    private static func manualScan(
        directory: URL,
        showHiddenFiles: Bool,
        followSymlinks: Bool
    ) throws -> [String] {
        let excludedNames: Set<String> = [
            ".git", "node_modules", ".build", "build", "DerivedData",
            "__pycache__", ".venv", "venv", "Pods", ".DS_Store", "dist",
            ".next", ".nuxt", ".svn", ".hg", ".tox"
        ]
        let excludedExts: Set<String> = [
            "png", "jpg", "jpeg", "gif", "ico", "svg", "webp",
            "mp3", "mp4", "wav", "avi", "mov",
            "zip", "tar", "gz", "rar", "7z",
            "exe", "dll", "so", "dylib", "o",
            "pdf", "doc", "docx", "xls", "xlsx"
        ]

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
            if excludedNames.contains(url.lastPathComponent) {
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
}
