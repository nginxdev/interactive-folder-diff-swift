import Foundation
import SwiftUI

enum DiffStatus: String, Codable {
    case unchanged
    case added
    case removed
    case modified
    case failure
}

class FileNode: Identifiable, ObservableObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    let id: UUID = UUID()
    let name: String
    let path: URL
    let isDirectory: Bool
    
    @Published var size: Int64
    @Published var children: [FileNode]?
    @Published var status: DiffStatus
    @Published var isExpanded: Bool = false
    
    /// Optional SHA256 hash of the file content.
    @Published var hash: String?
    
    /// Indicates if any child node contains a difference. Used for coloring parent directories.
    @Published var containsDiff: Bool = false
    
    // MARK: - State Management
    
    /// Recursively collects specific paths of all expanded directories.
    func getExpandedPaths() -> Set<String> {
        var paths = Set<String>()
        if isExpanded {
            paths.insert(path.path)
            if let children = children {
                for child in children {
                    paths.formUnion(child.getExpandedPaths())
                }
            }
        }
        return paths
    }
    
    /// Recursively restores expansion state based on a set of paths.
    func restoreExpansion(_ expandedPaths: Set<String>) {
        if expandedPaths.contains(path.path) {
            isExpanded = true
            if let children = children {
                for child in children {
                    child.restoreExpansion(expandedPaths)
                }
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initializes a new FileNode.
    ///
    /// - Parameters:
    ///   - url: The absolute URL of the file or directory.
    ///   - isDirectory: True if this node represents a directory.
    ///   - size: The size in bytes (defaults to 0).
    ///   - status: The initial diff status (defaults to `.unchanged`).
    init(url: URL, isDirectory: Bool, size: Int64 = 0, status: DiffStatus = .unchanged) {
        self.name = url.lastPathComponent
        self.path = url
        self.isDirectory = isDirectory
        self.size = size
        self.status = status
        self.children = isDirectory ? [] : nil
    }
}
