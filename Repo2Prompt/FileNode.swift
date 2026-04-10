import Foundation

// MARK: - Selection State

enum SelectionState {
    case all, some, none
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case dateAsc = "Date (Oldest)"
    case dateDesc = "Date (Newest)"
    case tokensAsc = "Tokens (Low-High)"
    case tokensDesc = "Tokens (High-Low)"
}

// MARK: - FileNode

@Observable
final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let relativePath: String
    let absolutePath: String
    let isDirectory: Bool
    let modificationDate: Date?
    let isGitIgnored: Bool

    var content: String?
    var tokenCount: Int = 0

    var children: [FileNode] = []
    weak var parent: FileNode?
    var isExpanded: Bool
    var needsLazyLoad: Bool
    var isLoadingChildren: Bool = false

    var isSelected: Bool = true {
        didSet {
            if isDirectory {
                for child in children {
                    child.isSelected = isSelected
                }
            }
        }
    }

    var isFilteredOut: Bool = false

    var selectionState: SelectionState {
        if !isDirectory { return isSelected ? .all : .none }
        if children.isEmpty { return isSelected ? .all : .none }
        let visible = children.filter { !$0.isFilteredOut }
        if visible.isEmpty { return .none }
        let allSelected = visible.allSatisfy { $0.selectionState == .all }
        let noneSelected = visible.allSatisfy { $0.selectionState == .none }
        if allSelected { return .all }
        if noneSelected { return .none }
        return .some
    }

    var effectiveTokenCount: Int {
        if isDirectory {
            return children
                .filter { !$0.isFilteredOut }
                .reduce(0) { $0 + $1.effectiveTokenCount }
        }
        return (isSelected && !isFilteredOut) ? tokenCount : 0
    }

    var selectedFileCount: Int {
        if isDirectory {
            return children.filter { !$0.isFilteredOut }.reduce(0) { $0 + $1.selectedFileCount }
        }
        return (isSelected && !isFilteredOut) ? 1 : 0
    }

    var selectedFiles: [(path: String, content: String)] {
        if isDirectory {
            return children.filter { !$0.isFilteredOut }.flatMap { $0.selectedFiles }
        }
        guard isSelected, !isFilteredOut, let content else { return [] }
        return [(path: relativePath, content: content)]
    }

    init(name: String, relativePath: String, absolutePath: String,
         isDirectory: Bool, modificationDate: Date? = nil,
         isGitIgnored: Bool = false,
         isSelected: Bool = true,
         isExpanded: Bool = true,
         needsLazyLoad: Bool = false) {
        self.name = name
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        self.isGitIgnored = isGitIgnored
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.needsLazyLoad = needsLazyLoad
    }

    // MARK: - Tree Operations

    func sortChildren(by order: SortOrder) {
        children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch order {
            case .nameAsc: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .dateAsc: return (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast)
            case .dateDesc: return (a.modificationDate ?? .distantPast) > (b.modificationDate ?? .distantPast)
            case .tokensAsc: return a.effectiveTokenCount < b.effectiveTokenCount
            case .tokensDesc: return a.effectiveTokenCount > b.effectiveTokenCount
            }
        }
        for child in children where child.isDirectory {
            child.sortChildren(by: order)
        }
    }

    func toggle() {
        switch selectionState {
        case .all: isSelected = false
        case .none, .some: isSelected = true
        }
    }

    // MARK: - Tree Rendering

    func renderTree(selectedOnly: Bool) -> String {
        var lines: [String] = [name + "/"]
        renderSubtree(prefix: "", selectedOnly: selectedOnly, into: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderSubtree(prefix: String, selectedOnly: Bool, into lines: inout [String]) {
        let visible: [FileNode]
        if selectedOnly {
            visible = children.filter { !$0.isFilteredOut && ($0.isDirectory ? $0.selectionState != .none : $0.isSelected) }
        } else {
            visible = children.filter { !$0.isFilteredOut }
        }
        for (i, child) in visible.enumerated() {
            let isLast = i == visible.count - 1
            let connector = isLast ? "└── " : "├── "
            let suffix = child.isDirectory ? "/" : ""
            lines.append(prefix + connector + child.name + suffix)
            if child.isDirectory {
                child.renderSubtree(
                    prefix: prefix + (isLast ? "    " : "│   "),
                    selectedOnly: selectedOnly,
                    into: &lines
                )
            }
        }
    }
}
