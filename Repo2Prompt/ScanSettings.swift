import Foundation

@Observable
final class ScanSettings {
    // Glob filters
    var includeGlob: String = "" { didSet { persist() } }
    var excludeGlob: String = "" { didSet { persist() } }

    // Output options
    var showLineNumbers: Bool = false { didSet { persist() } }
    var showHiddenFiles: Bool = false { didSet { persist() } }
    var followSymlinks: Bool = false { didSet { persist() } }
    var useAbsolutePaths: Bool = false { didSet { persist() } }
    var fullDirectoryTree: Bool = false { didSet { persist() } }
    var instruction: String = "" { didSet { persist() } }

    // Sort
    var sortOrder: SortOrder = .tokensDesc { didSet { persist() } }

    // Token map visibility
    var showTokenMap: Bool = true { didSet { persist() } }

    // MARK: - Persistence

    static let persistenceKey = "ScanSettings.v1"
    private let defaults: UserDefaults?
    private var isLoading = false

    private struct Snapshot: Codable {
        var includeGlob: String
        var excludeGlob: String
        var showLineNumbers: Bool
        var showHiddenFiles: Bool
        var followSymlinks: Bool
        var useAbsolutePaths: Bool
        var fullDirectoryTree: Bool
        var instruction: String
        var sortOrderRawValue: String
        var showTokenMap: Bool
    }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let defaults else { return }
        guard let data = defaults.data(forKey: Self.persistenceKey) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            isLoading = true
            defer { isLoading = false }
            includeGlob = snapshot.includeGlob
            excludeGlob = snapshot.excludeGlob
            showLineNumbers = snapshot.showLineNumbers
            showHiddenFiles = snapshot.showHiddenFiles
            followSymlinks = snapshot.followSymlinks
            useAbsolutePaths = snapshot.useAbsolutePaths
            fullDirectoryTree = snapshot.fullDirectoryTree
            instruction = snapshot.instruction
            if let order = SortOrder(rawValue: snapshot.sortOrderRawValue) {
                sortOrder = order
            }
            showTokenMap = snapshot.showTokenMap
        } catch {
            FileHandle.standardError.write(Data("ScanSettings: failed to decode persisted settings - \(error)\n".utf8))
        }
    }

    private func persist() {
        if isLoading { return }
        guard let defaults else { return }
        let snapshot = Snapshot(
            includeGlob: includeGlob,
            excludeGlob: excludeGlob,
            showLineNumbers: showLineNumbers,
            showHiddenFiles: showHiddenFiles,
            followSymlinks: followSymlinks,
            useAbsolutePaths: useAbsolutePaths,
            fullDirectoryTree: fullDirectoryTree,
            instruction: instruction,
            sortOrderRawValue: sortOrder.rawValue,
            showTokenMap: showTokenMap
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.persistenceKey)
        } catch {
            FileHandle.standardError.write(Data("ScanSettings: failed to encode settings - \(error)\n".utf8))
        }
    }

    // MARK: - Glob Matching

    func shouldIncludeFile(relativePath: String) -> Bool {
        let includePatterns = parsePatterns(includeGlob)
        let excludePatterns = parsePatterns(excludeGlob)

        let filename = (relativePath as NSString).lastPathComponent

        for pat in excludePatterns {
            if Self.matches(pat, path: relativePath, filename: filename) {
                return false
            }
        }

        if !includePatterns.isEmpty {
            let matchesAny = includePatterns.contains { pat in
                Self.matches(pat, path: relativePath, filename: filename)
            }
            if !matchesAny { return false }
        }

        return true
    }

    private static func matches(_ pattern: String, path: String, filename: String) -> Bool {
        if matchesGlob(path, pattern: pattern) { return true }
        if pattern.contains("/") { return false }
        return matchesGlob(filename, pattern: pattern)
    }

    static func matchesGlob(_ path: String, pattern: String) -> Bool {
        let regex = globToRegex(pattern)
        return path.range(of: regex, options: .regularExpression) != nil
    }

    static func globToRegex(_ glob: String) -> String {
        var regex = "^"
        var i = glob.startIndex
        var inClass = false

        while i < glob.endIndex {
            let c = glob[i]

            if inClass {
                switch c {
                case "]":
                    regex += "]"
                    inClass = false
                case "\\":
                    regex += "\\\\"
                default:
                    if "\\^".contains(c) {
                        regex += "\\\(c)"
                    } else {
                        regex += String(c)
                    }
                }
                i = glob.index(after: i)
                continue
            }

            switch c {
            case "*":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    let afterStars = glob.index(after: next)
                    let atStart = (i == glob.startIndex)
                    let prevIsSlash = !atStart && (glob[glob.index(before: i)] == "/")
                    let nextIsSlash = (afterStars < glob.endIndex) && (glob[afterStars] == "/")
                    let atEnd = (afterStars == glob.endIndex)

                    if atStart && nextIsSlash {
                        regex += "(?:.*/)?"
                        i = glob.index(after: afterStars)
                        continue
                    } else if prevIsSlash && nextIsSlash {
                        regex += "(?:.*/)?"
                        i = glob.index(after: afterStars)
                        continue
                    } else if prevIsSlash && atEnd {
                        regex += ".*"
                        i = afterStars
                        continue
                    } else {
                        regex += ".*"
                        i = afterStars
                        continue
                    }
                } else {
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "{":
                regex += "("
            case "}":
                regex += ")"
            case ",":
                regex += "|"
            case "[":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "!" {
                    regex += "[^"
                    i = glob.index(after: next)
                    inClass = true
                    continue
                } else {
                    regex += "["
                    inClass = true
                }
            case "]":
                regex += "\\]"
            default:
                if "\\^$.|+()".contains(c) {
                    regex += "\\\(c)"
                } else {
                    regex += String(c)
                }
            }
            i = glob.index(after: i)
        }
        regex += "$"
        return regex
    }

    private func parsePatterns(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Token Estimation

    static func estimateTokens(_ text: String) -> Int {
        var tokens = 0
        let scalars = text.unicodeScalars
        var i = scalars.startIndex

        while i < scalars.endIndex {
            let s = scalars[i]

            if s.properties.isWhitespace {
                tokens += 1
                i = scalars.index(after: i)
                while i < scalars.endIndex && scalars[i].properties.isWhitespace {
                    i = scalars.index(after: i)
                }
            } else if (s.value >= 0x41 && s.value <= 0x5A) ||
                      (s.value >= 0x61 && s.value <= 0x7A) ||
                      (s.value >= 0x30 && s.value <= 0x39) ||
                      s.value == 0x5F {
                var run = 0
                while i < scalars.endIndex {
                    let v = scalars[i].value
                    guard (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) ||
                          (v >= 0x30 && v <= 0x39) || v == 0x5F else { break }
                    run += 1
                    i = scalars.index(after: i)
                }
                tokens += max(1, (run + 2) / 3)
            } else if s.value < 0x80 {
                tokens += 1
                i = scalars.index(after: i)
            } else {
                tokens += 1
                i = scalars.index(after: i)
            }
        }
        return tokens
    }

    // MARK: - Prompt Generation

    func generatePrompt(root: FileNode) -> String {
        var output = ""

        let treeText = root.renderTree(selectedOnly: !fullDirectoryTree)
        output += "<directory_tree>\n\(treeText)</directory_tree>\n\n"

        let files = root.selectedFiles
        for file in files {
            let displayPath = useAbsolutePaths
                ? root.absolutePath + "/" + file.path
                : file.path
            var content = file.content
            if showLineNumbers {
                content = addLineNumbers(content)
            }
            output += "<file path=\"\(displayPath)\">\n\(content)\n</file>\n\n"
        }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstruction.isEmpty {
            output += "<instruction>\n\(trimmedInstruction)\n</instruction>\n"
        }

        return output
    }

    private func addLineNumbers(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let width = String(lines.count).count
        return lines.enumerated().map { i, line in
            let numString = String(i + 1)
            let padding = String(repeating: " ", count: width - numString.count)
            return "\(padding)\(numString) | \(line)"
        }.joined(separator: "\n")
    }
}
