import Foundation

// MARK: - Rule

/// A compiled gitignore rule ready for matching against a path.
nonisolated struct GitIgnoreRule: Sendable {
    let pattern: String
    let regex: NSRegularExpression
    let isNegation: Bool
    let isDirectoryOnly: Bool
}

// MARK: - Matcher

/// Rules from one .gitignore file, scoped to the directory that contains it.
/// `base` is the relative path of that directory from the scan root (`""` for root).
nonisolated struct GitIgnoreMatcher: Sendable {
    let rules: [GitIgnoreRule]
    let base: String

    /// Check whether a path (relative to the scan root) is covered by this matcher.
    /// Returns:
    /// - `true`  if the path is ignored by a rule in this file.
    /// - `false` if the path is un-ignored by a negation rule in this file.
    /// - `nil`   if no rule matches (caller should fall through to parent files).
    func match(relativePath: String, isDirectory: Bool) -> Bool? {
        let scoped: String
        if base.isEmpty {
            scoped = relativePath
        } else if relativePath == base {
            return nil
        } else if relativePath.hasPrefix(base + "/") {
            scoped = String(relativePath.dropFirst(base.count + 1))
        } else {
            return nil
        }

        // Within a single .gitignore, later rules override earlier ones, so iterate reversed.
        for rule in rules.reversed() {
            if rule.isDirectoryOnly && !isDirectory { continue }
            let range = NSRange(scoped.startIndex..<scoped.endIndex, in: scoped)
            if rule.regex.firstMatch(in: scoped, range: range) != nil {
                return !rule.isNegation
            }
        }
        return nil
    }
}

// MARK: - Stack

/// Stack of matchers effective while walking a directory tree.
/// Deeper .gitignore files override shallower ones.
nonisolated struct GitIgnoreStack {
    private var matchers: [GitIgnoreMatcher] = []

    var isEmpty: Bool { matchers.isEmpty }

    mutating func push(_ matcher: GitIgnoreMatcher) {
        matchers.append(matcher)
    }

    mutating func pop() {
        _ = matchers.popLast()
    }

    /// Walks deepest matcher first. First matcher with a definitive result wins.
    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        for matcher in matchers.reversed() {
            if let decision = matcher.match(relativePath: relativePath, isDirectory: isDirectory) {
                return decision
            }
        }
        return false
    }
}

// MARK: - Parser

nonisolated enum GitIgnoreParser {
    /// Parse the contents of a .gitignore file into a matcher scoped to `base`.
    static func parse(contents: String, base: String) -> GitIgnoreMatcher {
        var rules: [GitIgnoreRule] = []
        for rawLine in contents.components(separatedBy: "\n") {
            var line = rawLine
            if line.hasSuffix("\r") {
                line = String(line.dropLast())
            }
            line = trimTrailingUnescapedSpaces(line)
            if line.isEmpty { continue }
            if line.first == "#" { continue }
            if let rule = compileRule(line) {
                rules.append(rule)
            }
        }
        return GitIgnoreMatcher(rules: rules, base: base)
    }

    private static func compileRule(_ rawPattern: String) -> GitIgnoreRule? {
        var body = rawPattern

        var isNegation = false
        if body.first == "!" {
            isNegation = true
            body = String(body.dropFirst())
        } else if body.hasPrefix("\\!") {
            body = "!" + body.dropFirst(2)
        } else if body.hasPrefix("\\#") {
            body = "#" + body.dropFirst(2)
        }

        var isDirectoryOnly = false
        if body.hasSuffix("/") {
            isDirectoryOnly = true
            body = String(body.dropLast())
        }

        if body.isEmpty { return nil }

        // Per git docs: a leading "/" anchors to the .gitignore's directory; a pattern
        // containing any "/" is also anchored; otherwise it matches at any depth.
        var isAnchored = false
        if body.first == "/" {
            isAnchored = true
            body = String(body.dropFirst())
        } else if body.contains("/") {
            isAnchored = true
        }

        if body.isEmpty { return nil }

        let regexString = convertToRegex(pattern: body, isAnchored: isAnchored)
        guard let regex = try? NSRegularExpression(pattern: regexString) else { return nil }

        return GitIgnoreRule(
            pattern: rawPattern,
            regex: regex,
            isNegation: isNegation,
            isDirectoryOnly: isDirectoryOnly
        )
    }

    private static func convertToRegex(pattern: String, isAnchored: Bool) -> String {
        var regex = "^"
        if !isAnchored {
            regex += "(?:.*/)?"
        }

        let chars = Array(pattern)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            switch c {
            case "*":
                let next = i + 1
                if next < chars.count && chars[next] == "*" {
                    let afterStars = next + 1
                    let atStart = (i == 0)
                    let prevIsSlash = !atStart && chars[i - 1] == "/"
                    let nextIsSlash = afterStars < chars.count && chars[afterStars] == "/"
                    let atEnd = afterStars == chars.count

                    if (atStart || prevIsSlash) && nextIsSlash {
                        regex += "(?:.*/)?"
                        i = afterStars + 1
                        continue
                    } else if (atStart || prevIsSlash) && atEnd {
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
            case "[":
                var j = i + 1
                var body = ""
                if j < chars.count && chars[j] == "!" {
                    body += "^"
                    j += 1
                }
                var closed = false
                while j < chars.count {
                    let cc = chars[j]
                    if cc == "]" {
                        closed = true
                        break
                    }
                    if cc == "\\" || cc == "^" {
                        body += "\\"
                        body += String(cc)
                    } else {
                        body += String(cc)
                    }
                    j += 1
                }
                if closed {
                    regex += "[" + body + "]"
                    i = j + 1
                    continue
                } else {
                    regex += "\\["
                }
            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "\\":
                regex += "\\"
                regex += String(c)
            case "/":
                regex += "/"
            default:
                regex += String(c)
            }
            i += 1
        }

        regex += "$"
        return regex
    }

    private static func trimTrailingUnescapedSpaces(_ s: String) -> String {
        var chars = Array(s)
        while let last = chars.last, last == " " {
            var preceding = 0
            var idx = chars.count - 2
            while idx >= 0 && chars[idx] == "\\" {
                preceding += 1
                idx -= 1
            }
            if preceding % 2 == 1 {
                chars.remove(at: chars.count - 2)
                break
            }
            chars.removeLast()
        }
        return String(chars)
    }
}
