import Foundation
import CryptoKit

class FileSystemService: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = FileSystemService()
    
    // MARK: - Properties
    
    struct ScanOptions {
        var showHidden: Bool
        var showSystem: Bool
    }
    
    struct CompareOptions {
        var checkContent: Bool // Enable Hash Comparison
    }
    
    private let systemFiles = [".DS_Store", "Icon\r"]
    
    // MARK: - Scanning
    
    /// Recursively scans a directory and builds a `FileNode` tree.
    ///
    /// - Parameters:
    ///   - url: The file URL to start scanning from.
    ///   - options: Options to control filtering (hidden/system files).
    /// - Returns: A matching `FileNode`, or `nil` if the path doesn't exist.
    func scan(url: URL, options: ScanOptions) -> FileNode? {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return nil
        }
        
        let node = FileNode(url: url, isDirectory: isDir.boolValue)
        
        if isDir.boolValue {
            do {
                let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isHiddenKey]
                let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [])
                
                var size: Int64 = 0
                var children: [FileNode] = []
                
                for file in files {
                    let filename = file.lastPathComponent
                    
                    if !options.showHidden && filename.hasPrefix(".") { continue }
                    if !options.showSystem && systemFiles.contains(filename) { continue }
                    
                    if let child = scan(url: file, options: options) {
                        children.append(child)
                        size += child.size
                    }
                }
                
                node.children = children.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                node.size = size
                
            } catch {
                print("Error scanning \(url): \(error)")
                node.status = .failure
            }
        } else {
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attr[.size] as? Int64 {
                    node.size = fileSize
                }
            } catch {
                print("Error getting size for \(url): \(error)")
            }
        }
        
        return node
    }
    
    // MARK: - Comparison
    
    /// Compares two `FileNode` trees (Left vs Right) to identify differences.
    ///
    /// Updates the `status` and `containsDiff` properties of nodes in place.
    ///
    /// - Parameters:
    ///   - left: The root node of the left (source) tree.
    ///   - right: The root node of the right (target) tree.
    ///   - options: Configuration for comparison (e.g. checkContent).
    func compare(left: FileNode, right: FileNode, options: CompareOptions = CompareOptions(checkContent: false)) {
        guard let leftChildren = left.children, let rightChildren = right.children else { return }
        
        let leftMap = Dictionary(uniqueKeysWithValues: leftChildren.map { ($0.name, $0) })
        let rightMap = Dictionary(uniqueKeysWithValues: rightChildren.map { ($0.name, $0) })
        
        let allNames = Set(leftMap.keys).union(rightMap.keys)
        var anyDiff = false
        
        for name in allNames {
            let lNode = leftMap[name]
            let rNode = rightMap[name]
            
            if let l = lNode, let r = rNode {
                if l.isDirectory && r.isDirectory {
                    compare(left: l, right: r, options: options)
                    if l.status != .unchanged || l.containsDiff || r.status != .unchanged || r.containsDiff {
                        left.containsDiff = true
                        right.containsDiff = true
                        anyDiff = true
                    }
                } else if !l.isDirectory && !r.isDirectory {
                    // 1. Check Size (Quickest)
                    if l.size != r.size {
                        l.status = .modified
                        r.status = .modified
                        left.containsDiff = true
                        right.containsDiff = true
                        anyDiff = true
                    } 
                    // 2. Check Content Hash (If requested and sizes match)
                    else if options.checkContent {
                        let lHash = computeHash(url: l.path)
                        let rHash = computeHash(url: r.path)
                        
                        // Store hash for display
                        l.hash = lHash
                        r.hash = rHash
                        
                        if lHash != rHash {
                            l.status = .modified
                            r.status = .modified
                            left.containsDiff = true
                            right.containsDiff = true
                            anyDiff = true
                        }
                    }
                } else {
                    l.status = .modified
                    r.status = .modified
                    left.containsDiff = true
                    right.containsDiff = true
                    anyDiff = true
                }
            } else if let l = lNode {
                l.status = .removed
                setRecursiveStatus(l, status: .removed)
                left.containsDiff = true
                anyDiff = true
            } else if let r = rNode {
                r.status = .added
                setRecursiveStatus(r, status: .added)
                right.containsDiff = true
                anyDiff = true
            }
        }
        
        if anyDiff {
            left.containsDiff = true
            right.containsDiff = true
        }
    }
    
    // MARK: - Unified View
    
    /// Merges two trees into a single "Unified" Git-style tree.
    ///
    /// - Parameters:
    ///   - left: The original tree (Left).
    ///   - right: The modified tree (Right).
    /// - Returns: A new `FileNode` representing the unified state.
    func generateUnifiedTree(left: FileNode?, right: FileNode?) -> FileNode? {
        guard let left = left else { return right }
        guard let right = right else { return left }
        
        let unifiedRoot = FileNode(
            url: right.path,
            isDirectory: true,
             size: right.size
        )
        
        unifiedRoot.children = mergeChildren(left: left, right: right)
        unifiedRoot.status = right.status
        unifiedRoot.containsDiff = right.containsDiff || left.containsDiff
        
        return unifiedRoot
    }
    
    private func mergeChildren(left: FileNode, right: FileNode) -> [FileNode] {
        var merged: [FileNode] = []
        
        let leftChildren = left.children ?? []
        let rightChildren = right.children ?? []
        
        let leftMap = Dictionary(uniqueKeysWithValues: leftChildren.map { ($0.name, $0) })
        let rightMap = Dictionary(uniqueKeysWithValues: rightChildren.map { ($0.name, $0) })
        
        let allNames = Set(leftMap.keys).union(rightMap.keys).sorted()
        
        for name in allNames {
            let lNode = leftMap[name]
            let rNode = rightMap[name]
            
            if let l = lNode, let r = rNode {
                let newNode = FileNode(
                    url: r.path,
                    isDirectory: r.isDirectory,
                    size: r.size
                )
                newNode.status = r.status
                newNode.containsDiff = r.containsDiff
                
                if r.isDirectory {
                    newNode.children = mergeChildren(left: l, right: r)
                }
                merged.append(newNode)
                
            } else if let l = lNode {
                merged.append(l)
            } else if let r = rNode {
                merged.append(r)
            }
        }
        
        return merged
    }
    
    // MARK: - Helpers
    
    private func setRecursiveStatus(_ node: FileNode, status: DiffStatus) {
        node.status = status
        node.containsDiff = true
        if let children = node.children {
            for child in children {
                setRecursiveStatus(child, status: status)
            }
        }
    }
    
    /// Computes the SHA256 hash of a file.
    ///
    /// - Parameter url: The file URL.
    /// - Returns: A hex string representation of the hash, or "hash_error" if failed.
    private func computeHash(url: URL) -> String {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            var hasher = SHA256()
            while autoreleasepool(invoking: {
                let data = fileHandle.readData(ofLength: 1024 * 1024) // 1MB chunks
                if !data.isEmpty {
                    hasher.update(data: data)
                    return true
                }
                return false
            }) {}
            
            let digest = hasher.finalize()
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            print("Hash error for \(url): \(error)")
            return "hash_error"
        }
    }
    
    // MARK: - File Operations
    
    /// Copies a file or directory from source to destination.
    func copyItem(at source: URL, to destination: URL) throws {
        // Ensure parent directory exists
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        
        // Remove destination if it exists (Overwrite)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    /// Deletes the item at the specified URL.
    func deleteItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    /// Recursively syncs a node (file or folder) to destination.
    /// - Parameters:
    ///   - node: The source node to copy.
    ///   - destination: The destination URL.
    ///   - progress: Callback for progress reporting (bytesCopied, filename).
    func syncNode(_ node: FileNode, to destination: URL, progress: ((Int64, String) -> Void)? = nil) throws {
        if node.isDirectory {
            // Create directory
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            
            // Recurse children
            if let children = node.children {
                for child in children {
                    let childDest = destination.appendingPathComponent(child.name)
                    try syncNode(child, to: childDest, progress: progress)
                }
            }
        } else {
            // Copy File
            // Remove destination if it exists (Overwrite)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            
            // Ensure parent directory exists (for single file copy)
            let parent = destination.deletingLastPathComponent()
             if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            
            try FileManager.default.copyItem(at: node.path, to: destination)
            
            // Report progress
            progress?(node.size, node.name)
        }
    }
}
