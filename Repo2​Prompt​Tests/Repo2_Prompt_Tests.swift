import Testing
@testable import Repo2Prompt
import Foundation

// MARK: - Test Helpers

/// Creates a simple file node for testing.
private func makeFile(
    _ name: String,
    path: String = "",
    content: String? = nil,
    tokens: Int = 0,
    selected: Bool = true,
    filtered: Bool = false,
    date: Date? = nil
) -> FileNode {
    let node = FileNode(
        name: name,
        relativePath: path.isEmpty ? name : path,
        absolutePath: "/test/\(path.isEmpty ? name : path)",
        isDirectory: false,
        modificationDate: date
    )
    node.content = content
    node.tokenCount = tokens
    node.isSelected = selected
    node.isFilteredOut = filtered
    return node
}

/// Creates a directory node for testing.
private func makeDir(
    _ name: String,
    path: String = "",
    children: [FileNode] = [],
    date: Date? = nil,
    selected: Bool = true,
    expanded: Bool = true,
    ignored: Bool = false,
    needsLazyLoad: Bool = false
) -> FileNode {
    let node = FileNode(
        name: name,
        relativePath: path.isEmpty ? name : path,
        absolutePath: "/test/\(path.isEmpty ? name : path)",
        isDirectory: true,
        modificationDate: date,
        isGitIgnored: ignored,
        isSelected: selected,
        isExpanded: expanded,
        needsLazyLoad: needsLazyLoad
    )
    node.children = children
    for child in children {
        child.parent = node
    }
    return node
}

/// Builds a sample tree:
/// root/
///   src/
///     main.swift (100 tokens)
///     util.swift (50 tokens)
///   README.md (30 tokens)
private func makeSampleTree() -> FileNode {
    let main = makeFile("main.swift", path: "src/main.swift", content: "func main() {}", tokens: 100)
    let util = makeFile("util.swift", path: "src/util.swift", content: "func util() {}", tokens: 50)
    let src = makeDir("src", path: "src", children: [main, util])
    let readme = makeFile("README.md", path: "README.md", content: "# Hello", tokens: 30)
    let root = makeDir("root", path: "", children: [src, readme])
    root.absolutePath // already set in makeDir
    return root
}

// MARK: - FileNode: Initialization

@Suite("FileNode Initialization")
struct FileNodeInitTests {

    @Test func fileNodeProperties() {
        let date = Date()
        let node = FileNode(
            name: "test.swift",
            relativePath: "src/test.swift",
            absolutePath: "/repo/src/test.swift",
            isDirectory: false,
            modificationDate: date
        )
        #expect(node.name == "test.swift")
        #expect(node.relativePath == "src/test.swift")
        #expect(node.absolutePath == "/repo/src/test.swift")
        #expect(node.isDirectory == false)
        #expect(node.modificationDate == date)
        #expect(node.content == nil)
        #expect(node.tokenCount == 0)
        #expect(node.isSelected == true)
        #expect(node.isFilteredOut == false)
        #expect(node.children.isEmpty)
        #expect(node.parent == nil)
    }

    @Test func directoryNodeProperties() {
        let node = FileNode(
            name: "src",
            relativePath: "src",
            absolutePath: "/repo/src",
            isDirectory: true
        )
        #expect(node.isDirectory == true)
        #expect(node.modificationDate == nil)
    }
}

// MARK: - FileNode: Selection Propagation

@Suite("FileNode Selection")
struct FileNodeSelectionTests {

    @Test func fileSelectionState() {
        let file = makeFile("a.swift")
        #expect(file.selectionState == .all)
        file.isSelected = false
        #expect(file.selectionState == .none)
    }

    @Test func directorySelectsAllChildren() {
        let a = makeFile("a.swift")
        let b = makeFile("b.swift")
        let dir = makeDir("src", children: [a, b])

        dir.isSelected = false
        #expect(a.isSelected == false)
        #expect(b.isSelected == false)
        #expect(dir.selectionState == .none)
    }

    @Test func directoryDeselectsThenReselects() {
        let a = makeFile("a.swift")
        let b = makeFile("b.swift")
        let dir = makeDir("src", children: [a, b])

        dir.isSelected = false
        #expect(dir.selectionState == .none)
        dir.isSelected = true
        #expect(a.isSelected == true)
        #expect(b.isSelected == true)
        #expect(dir.selectionState == .all)
    }

    @Test func mixedSelectionState() {
        let a = makeFile("a.swift")
        let b = makeFile("b.swift")
        let dir = makeDir("src", children: [a, b])

        b.isSelected = false
        #expect(dir.selectionState == .some)
    }

    @Test func selectionStateIgnoresFilteredChildren() {
        let a = makeFile("a.swift", selected: true)
        let b = makeFile("b.swift", selected: false, filtered: true)
        let dir = makeDir("src", children: [a, b])

        // Only 'a' is visible and selected
        #expect(dir.selectionState == .all)
    }

    @Test func selectionStateAllFilteredReturnsNone() {
        let a = makeFile("a.swift", filtered: true)
        let dir = makeDir("src", children: [a])
        #expect(dir.selectionState == .none)
    }

    @Test func selectionStateEmptyDirReturnsNone() {
        let dir = makeDir("src", selected: false)
        #expect(dir.selectionState == .none)
    }

    @Test func selectionStateEmptySelectedDirReturnsAll() {
        let dir = makeDir("src")
        #expect(dir.selectionState == .all)
    }

    @Test func gitIgnoredDirectoryStartsCollapsedAndDeselected() {
        let dir = makeDir(
            "node_modules",
            path: "node_modules",
            selected: false,
            expanded: false,
            ignored: true,
            needsLazyLoad: true
        )
        #expect(dir.isGitIgnored == true)
        #expect(dir.isExpanded == false)
        #expect(dir.selectionState == .none)
        #expect(dir.needsLazyLoad == true)
    }

    @Test func nestedDirectoryPropagation() {
        let file = makeFile("a.swift")
        let inner = makeDir("inner", children: [file])
        let outer = makeDir("outer", children: [inner])

        outer.isSelected = false
        #expect(inner.isSelected == false)
        #expect(file.isSelected == false)
        #expect(outer.selectionState == .none)

        outer.isSelected = true
        #expect(file.isSelected == true)
        #expect(outer.selectionState == .all)
    }
}

// MARK: - FileNode: Toggle

@Suite("FileNode Toggle")
struct FileNodeToggleTests {

    @Test func toggleFileFromAllToNone() {
        let file = makeFile("a.swift")
        #expect(file.selectionState == .all)
        file.toggle()
        #expect(file.selectionState == .none)
    }

    @Test func toggleFileFromNoneToAll() {
        let file = makeFile("a.swift", selected: false)
        file.toggle()
        #expect(file.selectionState == .all)
    }

    @Test func toggleDirectoryFromAllToNone() {
        let a = makeFile("a.swift")
        let dir = makeDir("src", children: [a])
        #expect(dir.selectionState == .all)
        dir.toggle()
        #expect(dir.selectionState == .none)
        #expect(a.isSelected == false)
    }

    @Test func toggleDirectoryFromSomeToAll() {
        let a = makeFile("a.swift")
        let b = makeFile("b.swift", selected: false)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.selectionState == .some)
        dir.toggle()
        #expect(dir.selectionState == .all)
        #expect(b.isSelected == true)
    }

    @Test func toggleDirectoryFromNoneToAll() {
        let a = makeFile("a.swift", selected: false)
        let dir = makeDir("src", children: [a])
        #expect(dir.selectionState == .none)
        dir.toggle()
        #expect(dir.selectionState == .all)
    }
}

// MARK: - FileNode: Token Counts

@Suite("FileNode Token Counts")
struct FileNodeTokenTests {

    @Test func fileEffectiveTokenCountWhenSelected() {
        let file = makeFile("a.swift", tokens: 100)
        #expect(file.effectiveTokenCount == 100)
    }

    @Test func fileEffectiveTokenCountWhenDeselected() {
        let file = makeFile("a.swift", tokens: 100, selected: false)
        #expect(file.effectiveTokenCount == 0)
    }

    @Test func fileEffectiveTokenCountWhenFiltered() {
        let file = makeFile("a.swift", tokens: 100, filtered: true)
        #expect(file.effectiveTokenCount == 0)
    }

    @Test func directoryAggregatesTokens() {
        let a = makeFile("a.swift", tokens: 100)
        let b = makeFile("b.swift", tokens: 50)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.effectiveTokenCount == 150)
    }

    @Test func directoryExcludesDeselectedTokens() {
        let a = makeFile("a.swift", tokens: 100)
        let b = makeFile("b.swift", tokens: 50, selected: false)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.effectiveTokenCount == 100)
    }

    @Test func directoryExcludesFilteredTokens() {
        let a = makeFile("a.swift", tokens: 100)
        let b = makeFile("b.swift", tokens: 50, filtered: true)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.effectiveTokenCount == 100)
    }

    @Test func nestedDirectoryTokenAggregation() {
        let root = makeSampleTree()
        #expect(root.effectiveTokenCount == 180) // 100 + 50 + 30
    }
}

// MARK: - FileNode: Selected File Count

@Suite("FileNode File Count")
struct FileNodeFileCountTests {

    @Test func selectedFileCount() {
        let root = makeSampleTree()
        #expect(root.selectedFileCount == 3)
    }

    @Test func selectedFileCountWithDeselected() {
        let a = makeFile("a.swift", tokens: 10)
        let b = makeFile("b.swift", tokens: 10, selected: false)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.selectedFileCount == 1)
    }

    @Test func selectedFileCountWithFiltered() {
        let a = makeFile("a.swift", tokens: 10)
        let b = makeFile("b.swift", tokens: 10, filtered: true)
        let dir = makeDir("src", children: [a, b])
        #expect(dir.selectedFileCount == 1)
    }
}

// MARK: - FileNode: Selected Files

@Suite("FileNode Selected Files")
struct FileNodeSelectedFilesTests {

    @Test func returnsSelectedFilesWithContent() {
        let root = makeSampleTree()
        let files = root.selectedFiles
        #expect(files.count == 3)
        #expect(files[0].path == "src/main.swift")
        #expect(files[0].content == "func main() {}")
    }

    @Test func skipsDeselectedFiles() {
        let a = makeFile("a.swift", path: "a.swift", content: "aaa")
        let b = makeFile("b.swift", path: "b.swift", content: "bbb", selected: false)
        let dir = makeDir("root", children: [a, b])
        let files = dir.selectedFiles
        #expect(files.count == 1)
        #expect(files[0].path == "a.swift")
    }

    @Test func skipsFilteredFiles() {
        let a = makeFile("a.swift", path: "a.swift", content: "aaa")
        let b = makeFile("b.swift", path: "b.swift", content: "bbb", filtered: true)
        let dir = makeDir("root", children: [a, b])
        let files = dir.selectedFiles
        #expect(files.count == 1)
    }

    @Test func skipsFilesWithoutContent() {
        let a = makeFile("a.swift", path: "a.swift", content: nil)
        let dir = makeDir("root", children: [a])
        #expect(dir.selectedFiles.isEmpty)
    }
}

// MARK: - FileNode: Sorting

@Suite("FileNode Sorting")
struct FileNodeSortTests {

    @Test func sortByNameAsc() {
        let c = makeFile("c.swift")
        let a = makeFile("a.swift")
        let b = makeFile("b.swift")
        let dir = makeDir("root", children: [c, a, b])

        dir.sortChildren(by: .nameAsc)
        #expect(dir.children.map(\.name) == ["a.swift", "b.swift", "c.swift"])
    }

    @Test func sortByNameDesc() {
        let a = makeFile("a.swift")
        let c = makeFile("c.swift")
        let b = makeFile("b.swift")
        let dir = makeDir("root", children: [a, c, b])

        dir.sortChildren(by: .nameDesc)
        #expect(dir.children.map(\.name) == ["c.swift", "b.swift", "a.swift"])
    }

    @Test func sortByDateAsc() {
        let old = makeFile("old.swift", date: Date(timeIntervalSince1970: 100))
        let new = makeFile("new.swift", date: Date(timeIntervalSince1970: 200))
        let dir = makeDir("root", children: [new, old])

        dir.sortChildren(by: .dateAsc)
        #expect(dir.children.map(\.name) == ["old.swift", "new.swift"])
    }

    @Test func sortByDateDesc() {
        let old = makeFile("old.swift", date: Date(timeIntervalSince1970: 100))
        let new = makeFile("new.swift", date: Date(timeIntervalSince1970: 200))
        let dir = makeDir("root", children: [old, new])

        dir.sortChildren(by: .dateDesc)
        #expect(dir.children.map(\.name) == ["new.swift", "old.swift"])
    }

    @Test func sortByTokensAsc() {
        let big = makeFile("big.swift", tokens: 200)
        let small = makeFile("small.swift", tokens: 10)
        let dir = makeDir("root", children: [big, small])

        dir.sortChildren(by: .tokensAsc)
        #expect(dir.children.map(\.name) == ["small.swift", "big.swift"])
    }

    @Test func sortByTokensDesc() {
        let big = makeFile("big.swift", tokens: 200)
        let small = makeFile("small.swift", tokens: 10)
        let dir = makeDir("root", children: [small, big])

        dir.sortChildren(by: .tokensDesc)
        #expect(dir.children.map(\.name) == ["big.swift", "small.swift"])
    }

    @Test func directoriesSortBeforeFiles() {
        let file = makeFile("z_file.swift")
        let dir2 = makeDir("a_dir")
        let root = makeDir("root", children: [file, dir2])

        root.sortChildren(by: .nameAsc)
        #expect(root.children[0].name == "a_dir")
        #expect(root.children[1].name == "z_file.swift")
    }

    @Test func sortIsRecursive() {
        let b = makeFile("b.swift")
        let a = makeFile("a.swift")
        let inner = makeDir("inner", children: [b, a])
        let root = makeDir("root", children: [inner])

        root.sortChildren(by: .nameAsc)
        #expect(inner.children.map(\.name) == ["a.swift", "b.swift"])
    }

    @Test func sortByDateWithNilDates() {
        let noDate = makeFile("nodate.swift")
        let hasDate = makeFile("hasdate.swift", date: Date())
        let dir = makeDir("root", children: [hasDate, noDate])

        dir.sortChildren(by: .dateAsc)
        #expect(dir.children[0].name == "nodate.swift") // distantPast comes first
    }
}

// MARK: - FileNode: Tree Rendering

@Suite("FileNode Tree Rendering")
struct FileNodeTreeRenderTests {

    @Test func renderSimpleTree() {
        let a = makeFile("a.swift", path: "a.swift")
        let b = makeFile("b.swift", path: "b.swift")
        let root = makeDir("myproject", children: [a, b])

        let tree = root.renderTree(selectedOnly: false)
        #expect(tree.contains("myproject/"))
        #expect(tree.contains("├── a.swift"))
        #expect(tree.contains("└── b.swift"))
    }

    @Test func renderNestedTree() {
        let file = makeFile("main.swift", path: "src/main.swift")
        let src = makeDir("src", path: "src", children: [file])
        let root = makeDir("project", children: [src])

        let tree = root.renderTree(selectedOnly: false)
        #expect(tree.contains("└── src/"))
        #expect(tree.contains("    └── main.swift"))
    }

    @Test func renderTreeSelectedOnlyExcludesDeselected() {
        let a = makeFile("a.swift", path: "a.swift", content: "a")
        let b = makeFile("b.swift", path: "b.swift", content: "b", selected: false)
        let root = makeDir("project", children: [a, b])

        let tree = root.renderTree(selectedOnly: true)
        #expect(tree.contains("a.swift"))
        #expect(!tree.contains("b.swift"))
    }

    @Test func renderTreeFullIncludesDeselected() {
        let a = makeFile("a.swift", path: "a.swift", content: "a")
        let b = makeFile("b.swift", path: "b.swift", content: "b", selected: false)
        let root = makeDir("project", children: [a, b])

        let tree = root.renderTree(selectedOnly: false)
        #expect(tree.contains("a.swift"))
        #expect(tree.contains("b.swift"))
    }

    @Test func renderTreeExcludesFiltered() {
        let a = makeFile("a.swift", path: "a.swift")
        let b = makeFile("b.swift", path: "b.swift", filtered: true)
        let root = makeDir("project", children: [a, b])

        let tree = root.renderTree(selectedOnly: false)
        #expect(tree.contains("a.swift"))
        #expect(!tree.contains("b.swift"))
    }

    @Test func renderTreeDirectoryWithAllChildrenDeselectedHiddenInSelectedMode() {
        let a = makeFile("a.swift", path: "src/a.swift", selected: false)
        let src = makeDir("src", path: "src", children: [a])
        let root = makeDir("project", children: [src])

        let tree = root.renderTree(selectedOnly: true)
        #expect(!tree.contains("src"))
    }

    @Test func renderTreeEndsWithNewline() {
        let root = makeDir("project")
        let tree = root.renderTree(selectedOnly: false)
        #expect(tree.hasSuffix("\n"))
    }
}

// MARK: - ScanSettings: Glob to Regex

@Suite("Glob to Regex")
struct GlobToRegexTests {

    @Test func simpleWildcard() {
        let regex = ScanSettings.globToRegex("*.swift")
        #expect("main.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("src/main.swift".range(of: regex, options: .regularExpression) == nil) // * doesn't match /
    }

    @Test func doubleStarWildcard() {
        let regex = ScanSettings.globToRegex("**/*.swift")
        #expect("src/main.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("a/b/c/main.swift".range(of: regex, options: .regularExpression) != nil)
    }

    @Test func questionMark() {
        let regex = ScanSettings.globToRegex("file?.txt")
        #expect("file1.txt".range(of: regex, options: .regularExpression) != nil)
        #expect("fileAB.txt".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func braceExpansion() {
        let regex = ScanSettings.globToRegex("*.{swift,py}")
        #expect("main.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("main.py".range(of: regex, options: .regularExpression) != nil)
        #expect("main.js".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func characterClass() {
        let regex = ScanSettings.globToRegex("[abc].txt")
        #expect("a.txt".range(of: regex, options: .regularExpression) != nil)
        #expect("d.txt".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func dotEscaped() {
        let regex = ScanSettings.globToRegex("*.swift")
        // Dot in "swift" is literal, not regex wildcard
        #expect("main.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("mainxswift".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func specialCharsEscaped() {
        let regex = ScanSettings.globToRegex("file(1).txt")
        #expect("file(1).txt".range(of: regex, options: .regularExpression) != nil)
    }

    @Test func doubleStarAtStart() {
        let regex = ScanSettings.globToRegex("**/test.swift")
        #expect("test.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("a/b/test.swift".range(of: regex, options: .regularExpression) != nil)
    }

    @Test func doubleStarSkipsTrailingSlash() {
        let regex = ScanSettings.globToRegex("src/**/*.swift")
        #expect("src/main.swift".range(of: regex, options: .regularExpression) != nil)
        #expect("src/deep/main.swift".range(of: regex, options: .regularExpression) != nil)
    }

    @Test func doubleStarInMiddleMatchesZeroOrMoreComponents() {
        let regex = ScanSettings.globToRegex("**/.git/**")
        #expect(".git/config".range(of: regex, options: .regularExpression) != nil)
        #expect("a/b/.git/config".range(of: regex, options: .regularExpression) != nil)
        #expect("src/main.swift".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func negatedCharacterClass() {
        let regex = ScanSettings.globToRegex("[!abc].txt")
        #expect("d.txt".range(of: regex, options: .regularExpression) != nil)
        #expect("a.txt".range(of: regex, options: .regularExpression) == nil)
        #expect("b.txt".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func closingBracketOutsideClassEscaped() {
        let regex = ScanSettings.globToRegex("foo].txt")
        #expect("foo].txt".range(of: regex, options: .regularExpression) != nil)
        #expect("foo.txt".range(of: regex, options: .regularExpression) == nil)
    }

    @Test func specialCharsInsideClassNotTreatedAsRegex() {
        let regex = ScanSettings.globToRegex("[abc]*.txt")
        #expect("a1.txt".range(of: regex, options: .regularExpression) != nil)
        #expect("d1.txt".range(of: regex, options: .regularExpression) == nil)
    }
}

// MARK: - ScanSettings: matchesGlob

@Suite("Glob Matching")
struct GlobMatchingTests {

    @Test func matchesSimpleGlob() {
        #expect(ScanSettings.matchesGlob("main.swift", pattern: "*.swift") == true)
    }

    @Test func noMatchSimpleGlob() {
        #expect(ScanSettings.matchesGlob("main.py", pattern: "*.swift") == false)
    }

    @Test func matchesDeepPath() {
        #expect(ScanSettings.matchesGlob("src/main.swift", pattern: "**/*.swift") == true)
    }
}

// MARK: - ScanSettings: shouldIncludeFile

@Suite("File Include/Exclude")
struct ShouldIncludeFileTests {

    @Test func noPatternIncludesAll() {
        let settings = ScanSettings(defaults: nil)
        #expect(settings.shouldIncludeFile(relativePath: "anything.txt") == true)
    }

    @Test func includePatternFilters() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "*.swift"
        #expect(settings.shouldIncludeFile(relativePath: "main.swift") == true)
        #expect(settings.shouldIncludeFile(relativePath: "main.py") == false)
    }

    @Test func excludePatternFilters() {
        let settings = ScanSettings(defaults: nil)
        settings.excludeGlob = "*.lock"
        #expect(settings.shouldIncludeFile(relativePath: "Package.resolved") == true)
        #expect(settings.shouldIncludeFile(relativePath: "yarn.lock") == false)
    }

    @Test func excludeTakesPrecedence() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "*.swift"
        settings.excludeGlob = "generated.swift"
        #expect(settings.shouldIncludeFile(relativePath: "main.swift") == true)
        #expect(settings.shouldIncludeFile(relativePath: "generated.swift") == false)
    }

    @Test func commaSeparatedPatterns() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "*.swift, *.py"
        #expect(settings.shouldIncludeFile(relativePath: "main.swift") == true)
        #expect(settings.shouldIncludeFile(relativePath: "main.py") == true)
        #expect(settings.shouldIncludeFile(relativePath: "main.js") == false)
    }

    @Test func matchesAgainstFilename() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "*.swift"
        // Pattern *.swift matches "main.swift" filename even though full path has /
        #expect(settings.shouldIncludeFile(relativePath: "src/main.swift") == true)
    }

    @Test func excludeMatchesAgainstFilename() {
        let settings = ScanSettings(defaults: nil)
        settings.excludeGlob = "*.lock"
        #expect(settings.shouldIncludeFile(relativePath: "deps/package.lock") == false)
    }

    @Test func emptyPatternsIgnored() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "  ,  , "
        #expect(settings.shouldIncludeFile(relativePath: "anything.txt") == true)
    }

    @Test func pathPatternDoesNotFallBackToFilenameMatching() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "src/*.swift"
        #expect(settings.shouldIncludeFile(relativePath: "src/main.swift") == true)
        #expect(settings.shouldIncludeFile(relativePath: "foo.swift") == false)
        #expect(settings.shouldIncludeFile(relativePath: "other/foo.swift") == false)
    }

    @Test func excludePathPatternDoesNotFallBackToFilenameMatching() {
        let settings = ScanSettings(defaults: nil)
        settings.excludeGlob = "generated/*.swift"
        #expect(settings.shouldIncludeFile(relativePath: "generated/foo.swift") == false)
        #expect(settings.shouldIncludeFile(relativePath: "src/foo.swift") == true)
    }

    @Test func doubleStarMiddleExclude() {
        let settings = ScanSettings(defaults: nil)
        settings.excludeGlob = "**/.git/**"
        #expect(settings.shouldIncludeFile(relativePath: ".git/config") == false)
        #expect(settings.shouldIncludeFile(relativePath: "a/b/.git/config") == false)
        #expect(settings.shouldIncludeFile(relativePath: "src/main.swift") == true)
    }
}

// MARK: - ScanSettings: Token Estimation

@Suite("Token Estimation")
struct TokenEstimationTests {

    @Test func emptyString() {
        #expect(ScanSettings.estimateTokens("") == 0)
    }

    @Test func singleWord() {
        let tokens = ScanSettings.estimateTokens("hello")
        #expect(tokens >= 1)
        #expect(tokens <= 3)
    }

    @Test func whitespaceRunsCountAsOne() {
        let tokens = ScanSettings.estimateTokens("a     b")
        // "a" (1 token) + whitespace run (1 token) + "b" (1 token) = 3
        #expect(tokens == 3)
    }

    @Test func punctuationCountsAsOneEach() {
        let tokens = ScanSettings.estimateTokens("{}")
        #expect(tokens == 2)
    }

    @Test func longIdentifierSplitsIntoMultipleTokens() {
        // "calculateSomethingVeryLong" = 26 chars -> (26+2)/3 = 9 tokens
        let tokens = ScanSettings.estimateTokens("calculateSomethingVeryLong")
        #expect(tokens == 9)
    }

    @Test func shortIdentifierIsOneToken() {
        let tokens = ScanSettings.estimateTokens("x")
        #expect(tokens == 1)
    }

    @Test func threeCharIdentifierIsOneOrTwoTokens() {
        let tokens = ScanSettings.estimateTokens("foo")
        #expect(tokens >= 1 && tokens <= 2)
    }

    @Test func mixedCodeEstimate() {
        let code = "func main() { print(\"hello\") }"
        let tokens = ScanSettings.estimateTokens(code)
        // Should be reasonable for this snippet
        #expect(tokens > 5)
        #expect(tokens < 30)
    }

    @Test func nonASCII() {
        let tokens = ScanSettings.estimateTokens("cafe\u{0301}")  // café with combining accent
        #expect(tokens >= 2) // "cafe" + accent
    }

    @Test func numbersAreIdentifierLike() {
        let tokens = ScanSettings.estimateTokens("12345")
        #expect(tokens == 2) // (5+2)/3 = 2
    }

    @Test func underscoresArePartOfIdentifiers() {
        let tokens = ScanSettings.estimateTokens("my_var")
        #expect(tokens == 2) // (6+2)/3 = 2 (my_var is 6 chars including underscore)
    }

    @Test func tabsAndNewlinesAreWhitespace() {
        let tokens = ScanSettings.estimateTokens("a\t\n\n  b")
        #expect(tokens == 3) // a + whitespace run + b
    }
}

// MARK: - ScanSettings: Prompt Generation

@Suite("Prompt Generation")
struct PromptGenerationTests {

    @Test func basicPrompt() {
        let settings = ScanSettings(defaults: nil)
        let file = makeFile("main.swift", path: "main.swift", content: "let x = 1")
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains("<directory_tree>"))
        #expect(prompt.contains("</directory_tree>"))
        #expect(prompt.contains("<file path=\"main.swift\">"))
        #expect(prompt.contains("let x = 1"))
        #expect(prompt.contains("</file>"))
    }

    @Test func promptWithLineNumbers() {
        let settings = ScanSettings(defaults: nil)
        settings.showLineNumbers = true
        let file = makeFile("a.swift", path: "a.swift", content: "line1\nline2\nline3")
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains("1 | line1"))
        #expect(prompt.contains("2 | line2"))
        #expect(prompt.contains("3 | line3"))
    }

    @Test func promptWithAbsolutePaths() {
        let settings = ScanSettings(defaults: nil)
        settings.useAbsolutePaths = true
        let file = makeFile("a.swift", path: "a.swift", content: "code")
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains("<file path=\"/test/project/a.swift\">"))
    }

    @Test func promptWithRelativePaths() {
        let settings = ScanSettings(defaults: nil)
        settings.useAbsolutePaths = false
        let file = makeFile("a.swift", path: "a.swift", content: "code")
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains("<file path=\"a.swift\">"))
    }

    @Test func promptWithInstruction() {
        let settings = ScanSettings(defaults: nil)
        settings.instruction = "Review this code for bugs"
        let root = makeDir("project")

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains("<instruction>"))
        #expect(prompt.contains("Review this code for bugs"))
        #expect(prompt.contains("</instruction>"))
    }

    @Test func promptWithEmptyInstruction() {
        let settings = ScanSettings(defaults: nil)
        settings.instruction = "   \n  "
        let root = makeDir("project")

        let prompt = settings.generatePrompt(root: root)
        #expect(!prompt.contains("<instruction>"))
    }

    @Test func promptWithNoInstruction() {
        let settings = ScanSettings(defaults: nil)
        let root = makeDir("project")

        let prompt = settings.generatePrompt(root: root)
        #expect(!prompt.contains("<instruction>"))
    }

    @Test func promptFullDirectoryTreeShowsDeselected() {
        let settings = ScanSettings(defaults: nil)
        settings.fullDirectoryTree = true
        let a = makeFile("a.swift", path: "a.swift", content: "a")
        let b = makeFile("b.swift", path: "b.swift", content: "b", selected: false)
        let root = makeDir("project", children: [a, b])

        let prompt = settings.generatePrompt(root: root)
        // Tree should show both files
        #expect(prompt.contains("a.swift"))
        // But only selected file content is included
        let fileBlocks = prompt.components(separatedBy: "<file path=")
        #expect(fileBlocks.count == 2) // 1 file + 1 preamble
    }

    @Test func promptSelectedOnlyTreeHidesDeselected() {
        let settings = ScanSettings(defaults: nil)
        settings.fullDirectoryTree = false
        let a = makeFile("a.swift", path: "a.swift", content: "a")
        let b = makeFile("b.swift", path: "b.swift", content: "b", selected: false)
        let root = makeDir("project", children: [a, b])

        let prompt = settings.generatePrompt(root: root)
        let treeSection = prompt.components(separatedBy: "</directory_tree>")[0]
        #expect(treeSection.contains("a.swift"))
        #expect(!treeSection.contains("b.swift"))
    }

    @Test func lineNumbersPadding() {
        let settings = ScanSettings(defaults: nil)
        settings.showLineNumbers = true
        let lines = (1...12).map { "line\($0)" }.joined(separator: "\n")
        let file = makeFile("a.swift", path: "a.swift", content: lines)
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        #expect(prompt.contains(" 1 | line1"))
        #expect(prompt.contains("12 | line12"))
        #expect(!prompt.contains("1  | line1"))
    }

    @Test func promptOrderTreeThenFilesThenInstruction() {
        let settings = ScanSettings(defaults: nil)
        settings.instruction = "check it"
        let file = makeFile("a.swift", path: "a.swift", content: "code")
        let root = makeDir("project", children: [file])

        let prompt = settings.generatePrompt(root: root)
        let treePos = prompt.range(of: "<directory_tree>")!.lowerBound
        let filePos = prompt.range(of: "<file path=")!.lowerBound
        let instrPos = prompt.range(of: "<instruction>")!.lowerBound

        #expect(treePos < filePos)
        #expect(filePos < instrPos)
    }
}

// MARK: - FolderScanner: Integration Tests

@Suite("FolderScanner Integration")
struct FolderScannerTests {

    @Test func scanBuildsTreeFromTempDirectory() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")
        let srcDir = tmpDir.appendingPathComponent("src")

        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try "func main() {}".write(to: srcDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "# Hello".write(to: tmpDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        #expect(root.isDirectory == true)
        #expect(root.children.count == 2) // src/ and README.md

        let fileCount = root.selectedFileCount
        #expect(fileCount == 2)

        // Content should be loaded
        let files = root.selectedFiles
        #expect(files.count == 2)

        let mainFile = files.first { $0.path.hasSuffix("main.swift") }
        #expect(mainFile != nil)
        #expect(mainFile?.content == "func main() {}")
    }

    @Test func scanComputesTokenCounts() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "let x = 1".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        #expect(root.effectiveTokenCount > 0)
    }

    @Test func scanSkipsHiddenFilesByDefault() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "visible".write(to: tmpDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: tmpDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let files = root.selectedFiles
        #expect(files.count == 1)
        #expect(files[0].path == "visible.txt")
    }

    @Test func scanIncludesHiddenFilesWhenEnabled() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "visible".write(to: tmpDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: tmpDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: true,
            followSymlinks: false
        )

        let files = root.selectedFiles
        #expect(files.count == 2)
    }

    @Test func scanCompletesWithManyHiddenUntrackedFiles() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_hidden_spam_\(UUID().uuidString)")
        let hiddenDir = tmpDir.appendingPathComponent(".cache")

        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "visible".write(to: tmpDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        for index in 0..<4000 {
            let fileURL = hiddenDir.appendingPathComponent("hidden-\(index).txt")
            try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let files = root.selectedFiles
        #expect(files.count == 1)
        #expect(files[0].path == "visible.txt")
    }

    @Test func scanSkipsBinaryFiles() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "text content".write(to: tmpDir.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: tmpDir.appendingPathComponent("binary.bin"))

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let files = root.selectedFiles
        // binary.bin is discovered but its content is nil (contains null bytes)
        let textFile = files.first { $0.path == "text.txt" }
        #expect(textFile != nil)
        let binaryFile = files.first { $0.path == "binary.bin" }
        #expect(binaryFile == nil) // No content, so not in selectedFiles
    }

    @Test func scanSetsModificationDates() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "hello".write(to: tmpDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let fileNode = root.children.first
        #expect(fileNode?.modificationDate != nil)
    }

    @Test func scanSetsParentReferences() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_test_\(UUID().uuidString)")
        let srcDir = tmpDir.appendingPathComponent("src")

        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try "code".write(to: srcDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let src = root.children.first { $0.name == "src" }
        #expect(src?.parent === root)
        let file = src?.children.first
        #expect(file?.parent === src)
    }

    @Test func scanStartsDirectoriesCollapsed() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_collapsed_\(UUID().uuidString)")
        let nestedDir = tmpDir.appendingPathComponent("src/deep")

        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "code".write(to: nestedDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let src = root.children.first { $0.name == "src" }
        let deep = src?.children.first { $0.name == "deep" }

        #expect(src?.isExpanded == false)
        #expect(deep?.isExpanded == false)
    }

    @Test func scanCompletesWithManyFilesWithinTimeLimit() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_perf_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileCount = 5000
        let fanout = 50
        for bucket in 0..<(fileCount / fanout) {
            let bucketDir = tmpDir.appendingPathComponent("bucket_\(bucket)")
            try FileManager.default.createDirectory(at: bucketDir, withIntermediateDirectories: true)
            for index in 0..<fanout {
                let fileURL = bucketDir.appendingPathComponent("file_\(index).txt")
                try "x".write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }

        let start = Date()
        let root = try await FolderScanner.scan(
            directory: tmpDir,
            showHiddenFiles: false,
            followSymlinks: false
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(root.selectedFileCount == fileCount)
        #expect(elapsed < 10.0, "Scan of \(fileCount) files took \(elapsed)s, expected < 10s")
    }
}

// MARK: - GitIgnoreParser: Unit Tests

@Suite("GitIgnoreParser")
struct GitIgnoreParserTests {

    private func matcher(_ contents: String, base: String = "") -> GitIgnoreMatcher {
        GitIgnoreParser.parse(contents: contents, base: base)
    }

    @Test func commentsAndBlankLinesIgnored() {
        let m = matcher("""
        # comment

        build
        """)
        #expect(m.match(relativePath: "build", isDirectory: true) == true)
        #expect(m.match(relativePath: "# comment", isDirectory: false) == nil)
    }

    @Test func unanchoredPatternMatchesAtAnyDepth() {
        let m = matcher("node_modules")
        #expect(m.match(relativePath: "node_modules", isDirectory: true) == true)
        #expect(m.match(relativePath: "src/node_modules", isDirectory: true) == true)
        #expect(m.match(relativePath: "a/b/c/node_modules", isDirectory: true) == true)
    }

    @Test func anchoredPatternOnlyMatchesAtBase() {
        let m = matcher("/build")
        #expect(m.match(relativePath: "build", isDirectory: true) == true)
        #expect(m.match(relativePath: "src/build", isDirectory: true) == nil)
    }

    @Test func directoryOnlyPatternDoesNotMatchFiles() {
        let m = matcher("cache/")
        #expect(m.match(relativePath: "cache", isDirectory: true) == true)
        #expect(m.match(relativePath: "cache", isDirectory: false) == nil)
    }

    @Test func starMatchesWithinSinglePathComponent() {
        let m = matcher("*.log")
        #expect(m.match(relativePath: "app.log", isDirectory: false) == true)
        #expect(m.match(relativePath: "logs/app.log", isDirectory: false) == true)
        #expect(m.match(relativePath: "app.txt", isDirectory: false) == nil)
    }

    @Test func questionMarkMatchesSingleChar() {
        let m = matcher("file?.txt")
        #expect(m.match(relativePath: "file1.txt", isDirectory: false) == true)
        #expect(m.match(relativePath: "file12.txt", isDirectory: false) == nil)
    }

    @Test func characterClassMatches() {
        let m = matcher("file[abc].txt")
        #expect(m.match(relativePath: "filea.txt", isDirectory: false) == true)
        #expect(m.match(relativePath: "fileb.txt", isDirectory: false) == true)
        #expect(m.match(relativePath: "filed.txt", isDirectory: false) == nil)
    }

    @Test func negatedCharacterClassMatches() {
        let m = matcher("file[!abc].txt")
        #expect(m.match(relativePath: "filed.txt", isDirectory: false) == true)
        #expect(m.match(relativePath: "filea.txt", isDirectory: false) == nil)
    }

    @Test func doubleStarTrailingMatchesEverythingInside() {
        let m = matcher("vendor/**")
        #expect(m.match(relativePath: "vendor/lib.js", isDirectory: false) == true)
        #expect(m.match(relativePath: "vendor/a/b/c.js", isDirectory: false) == true)
    }

    @Test func doubleStarLeadingMatchesAtAnyDepth() {
        let m = matcher("**/foo")
        #expect(m.match(relativePath: "foo", isDirectory: false) == true)
        #expect(m.match(relativePath: "a/foo", isDirectory: false) == true)
        #expect(m.match(relativePath: "a/b/foo", isDirectory: false) == true)
    }

    @Test func doubleStarMiddleMatchesZeroOrMoreComponents() {
        let m = matcher("a/**/b")
        #expect(m.match(relativePath: "a/b", isDirectory: false) == true)
        #expect(m.match(relativePath: "a/x/b", isDirectory: false) == true)
        #expect(m.match(relativePath: "a/x/y/b", isDirectory: false) == true)
    }

    @Test func negationUnignoresPreviouslyMatched() {
        let m = matcher("""
        *.log
        !important.log
        """)
        #expect(m.match(relativePath: "debug.log", isDirectory: false) == true)
        #expect(m.match(relativePath: "important.log", isDirectory: false) == false)
    }

    @Test func scopedMatcherRespectsBase() {
        let m = matcher("secret.txt", base: "src")
        #expect(m.match(relativePath: "src/secret.txt", isDirectory: false) == true)
        #expect(m.match(relativePath: "secret.txt", isDirectory: false) == nil)
    }
}

// MARK: - GitIgnoreStack: Unit Tests

@Suite("GitIgnoreStack")
struct GitIgnoreStackTests {

    @Test func deeperMatcherOverridesShallower() {
        var stack = GitIgnoreStack()
        stack.push(GitIgnoreParser.parse(contents: "*.log", base: ""))
        stack.push(GitIgnoreParser.parse(contents: "!debug.log", base: "src"))

        #expect(stack.isIgnored(relativePath: "app.log", isDirectory: false) == true)
        #expect(stack.isIgnored(relativePath: "src/debug.log", isDirectory: false) == false)
        #expect(stack.isIgnored(relativePath: "src/other.log", isDirectory: false) == true)
    }

    @Test func emptyStackNothingIgnored() {
        let stack = GitIgnoreStack()
        #expect(stack.isIgnored(relativePath: "anything", isDirectory: false) == false)
    }
}

// MARK: - FolderScanner: .gitignore Integration

@Suite("FolderScanner GitIgnore")
struct FolderScannerGitIgnoreTests {

    private func makeTemp(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("repo2prompt_gi_\(label)_\(UUID().uuidString)")
    }

    @Test func rootGitignoreExcludesMatchingFiles() async throws {
        let tmp = makeTemp("root")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ".env\n*.log\n".write(to: tmp.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "a".write(to: tmp.appendingPathComponent("keep.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: tmp.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "c".write(to: tmp.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)

        let root = try await FolderScanner.scan(
            directory: tmp,
            showHiddenFiles: true,
            followSymlinks: false
        )

        let names = Set(root.selectedFiles.map { $0.path })
        #expect(names.contains("keep.swift"))
        #expect(!names.contains(".env"))
        #expect(!names.contains("app.log"))
    }

    @Test func ignoredDirectoryBecomesCollapsedPlaceholder() async throws {
        let tmp = makeTemp("dir")
        let sub = tmp.appendingPathComponent("vendor/inner")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "vendor/\n".write(to: tmp.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "x".write(to: sub.appendingPathComponent("lib.js"), atomically: true, encoding: .utf8)
        try "keep".write(to: tmp.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let root = try await FolderScanner.scan(
            directory: tmp,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let vendor = root.children.first { $0.name == "vendor" }
        #expect(vendor?.isDirectory == true)
        #expect(vendor?.isGitIgnored == true)
        #expect(vendor?.needsLazyLoad == true)
        #expect(vendor?.isExpanded == false)
        #expect(vendor?.children.isEmpty == true)

        let mainFile = root.children.first { $0.name == "main.swift" }
        #expect(mainFile != nil)
    }

    @Test func nestedGitignoreOverridesParent() async throws {
        let tmp = makeTemp("nested")
        let srcDir = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "*.log\n".write(to: tmp.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "!special.log\n".write(to: srcDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "x".write(to: tmp.appendingPathComponent("root.log"), atomically: true, encoding: .utf8)
        try "y".write(to: srcDir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "z".write(to: srcDir.appendingPathComponent("special.log"), atomically: true, encoding: .utf8)

        let root = try await FolderScanner.scan(
            directory: tmp,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let files = Set(root.selectedFiles.map { $0.path })
        #expect(files.contains("src/special.log"))
        #expect(!files.contains("src/debug.log"))
        #expect(!files.contains("root.log"))
    }

    @Test func materializeIgnoredDirectoryBypassesGitignore() async throws {
        let tmp = makeTemp("mat")
        let vendor = tmp.appendingPathComponent("vendor")
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "vendor/\n".write(to: tmp.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "inside".write(to: vendor.appendingPathComponent("lib.js"), atomically: true, encoding: .utf8)

        let root = try await FolderScanner.scan(
            directory: tmp,
            showHiddenFiles: false,
            followSymlinks: false
        )

        let vendorNode = root.children.first { $0.name == "vendor" }!
        #expect(vendorNode.needsLazyLoad == true)

        try await FolderScanner.materializeIgnoredDirectory(
            vendorNode,
            showHiddenFiles: false,
            followSymlinks: false
        )

        #expect(vendorNode.needsLazyLoad == false)
        #expect(vendorNode.children.contains { $0.name == "lib.js" })
    }
}

// MARK: - SortOrder Enum

@Suite("SortOrder")
struct SortOrderTests {

    @Test func allCasesExist() {
        #expect(SortOrder.allCases.count == 6)
    }

    @Test func rawValues() {
        #expect(SortOrder.nameAsc.rawValue == "Name (A-Z)")
        #expect(SortOrder.nameDesc.rawValue == "Name (Z-A)")
        #expect(SortOrder.dateAsc.rawValue == "Date (Oldest)")
        #expect(SortOrder.dateDesc.rawValue == "Date (Newest)")
        #expect(SortOrder.tokensAsc.rawValue == "Tokens (Low-High)")
        #expect(SortOrder.tokensDesc.rawValue == "Tokens (High-Low)")
    }
}

// MARK: - SelectionState Enum

@Suite("SelectionState")
struct SelectionStateTests {

    @Test func allCasesAccessible() {
        let all = SelectionState.all
        let some = SelectionState.some
        let none = SelectionState.none
        #expect(all != none)
        #expect(some != all)
        #expect(some != none)
    }
}

// MARK: - ScanSettings: Persistence

@Suite("ScanSettings Persistence", .serialized)
struct ScanSettingsPersistenceTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Repo2PromptTests.ScanSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func settingsPersistAcrossInstances() {
        let defaults = makeDefaults()

        let first = ScanSettings(defaults: defaults)
        first.includeGlob = "*.swift"
        first.excludeGlob = "*.lock"
        first.showLineNumbers = true
        first.useAbsolutePaths = true
        first.fullDirectoryTree = true
        first.showHiddenFiles = true
        first.followSymlinks = true
        first.instruction = "Look for bugs"
        first.sortOrder = .nameAsc
        first.showTokenMap = false

        let second = ScanSettings(defaults: defaults)
        #expect(second.includeGlob == "*.swift")
        #expect(second.excludeGlob == "*.lock")
        #expect(second.showLineNumbers == true)
        #expect(second.useAbsolutePaths == true)
        #expect(second.fullDirectoryTree == true)
        #expect(second.showHiddenFiles == true)
        #expect(second.followSymlinks == true)
        #expect(second.instruction == "Look for bugs")
        #expect(second.sortOrder == .nameAsc)
        #expect(second.showTokenMap == false)
    }

    @Test func defaultsWhenNothingPersisted() {
        let defaults = makeDefaults()

        let settings = ScanSettings(defaults: defaults)
        #expect(settings.includeGlob == "")
        #expect(settings.excludeGlob == "")
        #expect(settings.showLineNumbers == false)
        #expect(settings.sortOrder == .tokensDesc)
        #expect(settings.showTokenMap == true)
    }

    @Test func corruptedDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: ScanSettings.persistenceKey)

        let settings = ScanSettings(defaults: defaults)
        #expect(settings.includeGlob == "")
        #expect(settings.sortOrder == .tokensDesc)
    }

    @Test func nilDefaultsDoesNotPersist() {
        let settings = ScanSettings(defaults: nil)
        settings.includeGlob = "*.swift"

        let other = ScanSettings(defaults: nil)
        #expect(other.includeGlob == "")
    }
}
