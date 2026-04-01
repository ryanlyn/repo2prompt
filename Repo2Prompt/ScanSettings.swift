import Foundation

@Observable
final class ScanSettings {
    // Glob filters
    var includeGlob: String = ""
    var excludeGlob: String = ""

    // Output options
    var showLineNumbers: Bool = false
    var includeGitDiff: Bool = false
    var showHiddenFiles: Bool = false
    var followSymlinks: Bool = false
    var useAbsolutePaths: Bool = false
    var fullDirectoryTree: Bool = false
    var instruction: String = ""

    // Sort
    var sortOrder: SortOrder = .tokensDesc

    // Token map visibility
    var showTokenMap: Bool = true

    // MARK: - Glob Matching

    func shouldIncludeFile(relativePath: String) -> Bool {
        let includePatterns = parsePatterns(includeGlob)
        let excludePatterns = parsePatterns(excludeGlob)

        let filename = (relativePath as NSString).lastPathComponent

        for pat in excludePatterns {
            if Self.matchesGlob(relativePath, pattern: pat) ||
               Self.matchesGlob(filename, pattern: pat) {
                return false
            }
        }

        if !includePatterns.isEmpty {
            let matchesAny = includePatterns.contains { pat in
                Self.matchesGlob(relativePath, pattern: pat) ||
                Self.matchesGlob(filename, pattern: pat)
            }
            if !matchesAny { return false }
        }

        return true
    }

    static func matchesGlob(_ path: String, pattern: String) -> Bool {
        let regex = globToRegex(pattern)
        return path.range(of: regex, options: .regularExpression) != nil
    }

    static func globToRegex(_ glob: String) -> String {
        var regex = "^"
        var i = glob.startIndex
        while i < glob.endIndex {
            let c = glob[i]
            switch c {
            case "*":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    regex += ".*"
                    i = glob.index(after: next)
                    if i < glob.endIndex && glob[i] == "/" {
                        i = glob.index(after: i)
                    }
                    continue
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
                regex += "["
            case "]":
                regex += "]"
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

    func generatePrompt(root: FileNode, gitDiff: String?) -> String {
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

        if includeGitDiff, let diff = gitDiff, !diff.isEmpty {
            output += "<git_diff>\n\(diff)\n</git_diff>\n\n"
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
            let num = String(i + 1).padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(num) | \(line)"
        }.joined(separator: "\n")
    }
}
