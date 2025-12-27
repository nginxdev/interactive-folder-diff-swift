import SwiftUI

/// A list row view represeting a single file or directory.
///
/// Displays:
/// - Icon (Folder/File)
/// - Filename
/// - Status Badge (Added/Removed/Modified/Sync labels)
/// - File Size
struct FileRowView: View {
    
    // MARK: - Properties
    
    @ObservedObject var node: FileNode
    var side: CompareViewModel.Side? // nil means Unified or Unknown
    
    @EnvironmentObject var viewModel: CompareViewModel
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 20)
            
            Text(node.name)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
            
            // MARK: - Action Buttons (On Hover)
            if isHovering {
                HStack(spacing: 4) {
                    // Delete Button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Item")
                    
                    // Copy/Sync Button
                    if let side = side {
                        Button(action: {
                            viewModel.copyNode(node, from: side)
                        }) {
                            Image(systemName: copyIconName(for: side))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help(node.isDirectory ? "Sync Copy Folder" : "Copy File")
                    }
                }
                .padding(.leading, 8)
                .transition(.opacity)
            }
            
            Spacer()
            
            if node.status != .unchanged {
                statusBadge
            } else if node.containsDiff {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .help("Contains differences inside")
            }
            
            if !node.isDirectory {
                if let hash = node.hash {
                    Text(String(hash.prefix(7)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .background(.tertiary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .help("SHA256: \(hash)")
                }
            }
            
            Text(formattedSize)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .alert("Delete \(node.name)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteNode(node)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var iconName: String {
        node.isDirectory ? "folder.fill" : "doc"
    }
    
    private var iconColor: Color {
        node.isDirectory ? .blue : .secondary
    }
    
    /// Returns the semantic status badge based on the current ViewMode.
    @ViewBuilder
    private var statusBadge: some View {
        switch (viewModel.viewMode, node.status) {
        
        // Sync Mode: Focus on Left vs Right existence
        case (.sync, .removed):
            Text("Left Only")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1), in: Capsule())
                .foregroundStyle(.blue)
                
        case (.sync, .added):
            Text("Right Only")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1), in: Capsule())
                .foregroundStyle(.purple)
                
        // Git Mode: Focus on Added/Removed history
        case (.gitSplit, .removed), (.gitUnified, .removed):
             Text("Removed")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.1), in: Capsule())
                .foregroundStyle(.red)

        case (.gitSplit, .added), (.gitUnified, .added):
            Text("Added")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.1), in: Capsule())
                .foregroundStyle(.green)
                
        case (_, .modified):
             Text("Modified")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1), in: Capsule())
                .foregroundStyle(.orange)
                
        default:
            EmptyView()
        }
    }
    
    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: node.size)
    }
    private func copyIconName(for side: CompareViewModel.Side) -> String {
        switch side {
        case .left:
            return "arrow.right.circle.fill" // Copy Left -> Right
        case .right:
            return "arrow.left.circle.fill" // Copy Right -> Left
        }
    }
}
