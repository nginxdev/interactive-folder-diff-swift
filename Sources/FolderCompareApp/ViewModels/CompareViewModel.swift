import SwiftUI
import Combine
import AppKit

@MainActor
class CompareViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var leftRoot: FileNode?
    @Published var rightRoot: FileNode?
    @Published var unifiedRoot: FileNode?
    
    @Published var leftPath: URL?
    @Published var rightPath: URL?
    
    @Published var showHidden: Bool = false
    @Published var showSystem: Bool = false
    @Published var diffOnly: Bool = false
    @Published var checkContent: Bool = false
    @Published var searchText: String = ""
    
    // MARK: - Progress State
    
    struct CopyProgress {
        var totalBytes: Int64 = 0
        var bytesCopied: Int64 = 0
        var totalFiles: Int = 0
        var filesCopied: Int = 0
        var currentFile: String = ""
        
        var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesCopied) / Double(totalBytes)
        }
    }
    
    @Published var copyProgress: CopyProgress?
    @Published var isCopying: Bool = false
    
    @Published var viewMode: ViewMode = .sync
    @Published var isScanning: Bool = false
    
    // MARK: - Types
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case sync = "Sync"
        case gitSplit = "Split"
        case gitUnified = "Unified"
        var id: String { rawValue }
    }
    
    // MARK: - Dependencies
    
    private let service = FileSystemService.shared
    
    // MARK: - Actions
    
    /// Triggers the scanning and comparison of selected folders.
    ///
    /// This method runs asynchronously on a background thread:
    /// 1. Scans both Left and Right directories.
    /// 2. Performs a comparison to optimize for side-by-side viewing.
    /// 3. Generates a Unified tree for the Git-style view.
    /// 4. Updates published properties on the Main Actor.
    func loadFolders() {
        guard let lPath = leftPath, let rPath = rightPath else { return }
        
        // 1. Capture current expansion state
        var expandedPaths = Set<String>()
        if let l = leftRoot { expandedPaths.formUnion(l.getExpandedPaths()) }
        if let r = rightRoot { expandedPaths.formUnion(r.getExpandedPaths()) }
        if let u = unifiedRoot { expandedPaths.formUnion(u.getExpandedPaths()) }
        
        isScanning = true
        
        let showHidden = self.showHidden
        let showSystem = self.showSystem
        let checkContent = self.checkContent
        
        Task.detached {
            let options = FileSystemService.ScanOptions(showHidden: showHidden, showSystem: showSystem)
            let compareOptions = FileSystemService.CompareOptions(checkContent: checkContent)
            
            let lNode = FileSystemService.shared.scan(url: lPath, options: options)
            let rNode = FileSystemService.shared.scan(url: rPath, options: options)
            
            if let l = lNode, let r = rNode {
                FileSystemService.shared.compare(left: l, right: r, options: compareOptions)
            }
            
            let uNode = FileSystemService.shared.generateUnifiedTree(left: lNode, right: rNode)
            
            await MainActor.run {
                // 2. Restore expansion state
                if let l = lNode { l.restoreExpansion(expandedPaths) }
                if let r = rNode { r.restoreExpansion(expandedPaths) }
                if let u = uNode { u.restoreExpansion(expandedPaths) }
                
                self.leftRoot = lNode
                self.rightRoot = rNode
                self.unifiedRoot = uNode
                self.isScanning = false
            }
        }
    }
    
    /// Opens the native system dialog to select the Left source folder.
    func selectLeftFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.leftPath = url
            if rightPath != nil { loadFolders() }
        }
    }
    
    /// Opens the native system dialog to select the Right source folder.
    func selectRightFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.rightPath = url
            if leftPath != nil { loadFolders() }
        }
    }
    
    /// Re-runs the scan and comparison logic.
    func refresh() {
        loadFolders()
    }
    
    // MARK: - File Management
    
    enum Side {
        case left, right
    }
    
    /// Copies a node from one side to the other.
    func copyNode(_ node: FileNode, from side: Side) {
        guard let leftBase = leftPath, let rightBase = rightPath else { return }
        
        let sourceURL = node.path
        let destinationURL: URL
        
        // Calculate relative path
        let sourceBase = (side == .left) ? leftBase : rightBase
        let targetBase = (side == .left) ? rightBase : leftBase
        
        // Safety: Unlikely to fail if logic is correct, but robust path handling needed
        let pathComponents = sourceURL.pathComponents
        let baseComponents = sourceBase.pathComponents
        
        if pathComponents.count >= baseComponents.count {
            let relativeComponents = pathComponents.dropFirst(baseComponents.count)
            destinationURL = relativeComponents.reduce(targetBase) { $0.appendingPathComponent($1) }
            
            // 1. Calculate Totals
            let totals = calculateTotals(for: node)
            self.copyProgress = CopyProgress(totalBytes: totals.bytes, totalFiles: totals.files)
            self.isCopying = true
            
            // Perform Copy
            Task.detached {
                do {
                    try FileSystemService.shared.syncNode(node, to: destinationURL) { bytes, name in
                        Task { @MainActor in
                            if var progress = self.copyProgress {
                                progress.bytesCopied += bytes
                                progress.filesCopied += 1
                                progress.currentFile = name
                                self.copyProgress = progress
                            }
                        }
                    }
                    
                    await MainActor.run {
                        self.isCopying = false
                        self.copyProgress = nil
                        self.refresh() // Auto-refresh after action
                    }
                } catch {
                    print("Copy failed: \(error)")
                    await MainActor.run {
                        self.isCopying = false
                        self.copyProgress = nil
                    }
                }
            }
        }
    }
    
    /// Deletes the specified node.
    func deleteNode(_ node: FileNode) {
        Task.detached {
            do {
                try FileSystemService.shared.deleteItem(at: node.path)
                await MainActor.run {
                    self.refresh()
                }
            } catch {
                print("Delete failed: \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateTotals(for node: FileNode) -> (bytes: Int64, files: Int) {
        var bytes: Int64 = 0
        var files: Int = 0
        
        if node.isDirectory {
            if let children = node.children {
                for child in children {
                    let result = calculateTotals(for: child)
                    bytes += result.bytes
                    files += result.files
                }
            }
        } else {
            bytes = node.size
            files = 1
        }
        
        return (bytes, files)
    }
}
