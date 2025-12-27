import SwiftUI

/// A recursive tree view that displays `FileNode` hierarchies.
///
/// Uses `MovableOutlineGroup` to construct the tree structure.
struct TreeView: View {
    
    // MARK: - Properties
    
    @ObservedObject var root: FileNode
    var diffOnly: Bool
    var side: CompareViewModel.Side? // Context
    var searchText: String // Filter
    
    // MARK: - Body
    
    var body: some View {
        List {
            MovableOutlineGroup(node: root, diffOnly: diffOnly, side: side, searchText: searchText)
        }
    }
}

/// A recursive component for rendering tree nodes.
///
/// Handles:
/// - Recursion via `ForEach`
/// - Filtering based on `diffOnly` state and `searchText`
/// - Expansion/Collapse using `DisclosureGroup`
struct MovableOutlineGroup: View {
    
    // MARK: - Properties
    
    @ObservedObject var node: FileNode
    var diffOnly: Bool
    var side: CompareViewModel.Side?
    var searchText: String
    
    // MARK: - Body
    
    var body: some View {
        if node.isDirectory {
            // Filter children based on Diff AND Search
            let visibleChildren = node.children?.filter { child in
                shouldShow(child)
            } ?? []
            
            if !visibleChildren.isEmpty {
                // Auto-expand if searching
                let isExpandedBinding = Binding(
                    get: { !searchText.isEmpty || node.isExpanded },
                    set: { node.isExpanded = $0 }
                )
                
                DisclosureGroup(
                    isExpanded: isExpandedBinding,
                    content: {
                        ForEach(visibleChildren) { child in
                            AnyView(MovableOutlineGroup(node: child, diffOnly: diffOnly, side: side, searchText: searchText))
                        }
                    },
                    label: {
                        FileRowView(node: node, side: side)
                            .onTapGesture {
                                withAnimation {
                                    node.isExpanded.toggle()
                                }
                            }
                    }
                )
            } else {
               // Show folder if it matches search itself/diff criteria (even if empty of matching children)
               if shouldShow(node) {
                   FileRowView(node: node, side: side)
               }
            }
        } else {
            if shouldShow(node) {
                FileRowView(node: node, side: side)
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Determines if a node should be visible based on current filters.
    private func shouldShow(_ child: FileNode) -> Bool {
        // 1. Diff Check
        if diffOnly && child.status == .unchanged && !child.containsDiff {
            return false
        }
        
        // 2. Search Check
        if !searchText.isEmpty {
            return matchesSearch(child, text: searchText)
        }
        
        return true
    }
    
    /// Recursive search match (Match Self OR Match Descendant)
    private func matchesSearch(_ child: FileNode, text: String) -> Bool {
        if child.name.localizedCaseInsensitiveContains(text) {
            return true
        }
        if let children = child.children {
            return children.contains { matchesSearch($0, text: text) }
        }
        return false
    }
}
