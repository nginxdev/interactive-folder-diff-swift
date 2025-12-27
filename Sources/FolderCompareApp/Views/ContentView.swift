import SwiftUI
import AppKit

struct ContentView: View {
    
    // MARK: - State
    
    @StateObject private var viewModel = CompareViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showAbout = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } detail: {
            ZStack {
                if viewModel.leftPath == nil || viewModel.rightPath == nil {
                    ContentUnavailableView(
                        "Select Folders",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Choose source folders from the sidebar to start comparing.")
                    )
                } else {
                    splitViewContent
                }
            }
            .overlay { loadingOverlay }
            .safeAreaInset(edge: .bottom) {
                copyProgressOverlay
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(viewModel)
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        Form {
            Section("Left Source") {
                if let url = viewModel.leftPath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Choose or drag and drop a folder...")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                
                Button(action: {
                    viewModel.selectLeftFolder()
                }) {
                    Label("Choose Folder...", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, error in
                    guard let data = data, let path = String(data: data, encoding: .utf8), let url = URL(string: path) else { return }
                    DispatchQueue.main.async {
                        viewModel.leftPath = url
                        if viewModel.rightPath != nil { viewModel.loadFolders() }
                    }
                }
                return true
            }
            
            Section("Right Source") {
                if let url = viewModel.rightPath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Choose or drag and drop a folder...")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                
                Button(action: {
                    viewModel.selectRightFolder()
                }) {
                    Label("Choose Folder...", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, error in
                    guard let data = data, let path = String(data: data, encoding: .utf8), let url = URL(string: path) else { return }
                    DispatchQueue.main.async {
                        viewModel.rightPath = url
                        if viewModel.leftPath != nil { viewModel.loadFolders() }
                    }
                }
                return true
            }
            
            Section("View Options") {
                Toggle(isOn: $viewModel.showHidden) {
                    Label("Hidden Files", systemImage: "eye")
                }
                .onChange(of: viewModel.showHidden) { viewModel.refresh() }
                
                Toggle(isOn: $viewModel.showSystem) {
                    Label("System Files", systemImage: "gear.badge")
                }
                .onChange(of: viewModel.showSystem) { viewModel.refresh() }
                
                Toggle(isOn: $viewModel.diffOnly) {
                    Label("Diff Only", systemImage: "arrow.left.and.right.square")
                }
                
                Toggle(isOn: $viewModel.checkContent) {
                    Label("Compare Content", systemImage: "doc.text.magnifyingglass")
                }
                .help("Calculates SHA256 hashes for files with identical sizes to ensure they are truly identical.")
                .onChange(of: viewModel.checkContent) { viewModel.refresh() }
                
                Picker("Mode", selection: $viewModel.viewMode) {
                    ForEach(CompareViewModel.ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .tint(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(action: { showAbout = true }) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("About Interactive folder diff")
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .searchable(text: $viewModel.searchText, placement: .sidebar, prompt: "Filter files...")
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var splitViewContent: some View {
        switch viewModel.viewMode {
        case .sync, .gitSplit:
            HSplitView {
                LeftPanelView(root: viewModel.leftRoot, diffOnly: viewModel.diffOnly)
                    .frame(minWidth: 300, maxWidth: .infinity)
                
                RightPanelView(root: viewModel.rightRoot, diffOnly: viewModel.diffOnly)
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            .toolbar { mainToolbar }
        case .gitUnified:
            UnifiedPanelView(root: viewModel.unifiedRoot, diffOnly: viewModel.diffOnly)
                .toolbar { mainToolbar }
        }
    }
    
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                viewModel.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Comparison")
            .disabled(viewModel.isScanning)
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isScanning {
            ZStack {
                Color.black.opacity(0.1)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 10, y: 5)
            }
        }
    }
    
    @ViewBuilder
    private var copyProgressOverlay: some View {
        if viewModel.isCopying, let progress = viewModel.copyProgress {
             VStack(spacing: 12) {
                 HStack {
                     Text("Copying \(progress.currentFile)...")
                         .font(.headline)
                     Spacer()
                     Text("\(Int(progress.fraction * 100))%")
                         .font(.subheadline)
                         .monospacedDigit()
                         .foregroundStyle(.secondary)
                 }
                 
                 ProgressView(value: progress.fraction)
                     .progressViewStyle(.linear)
                 
                 HStack {
                     Text("\(progress.filesCopied) / \(progress.totalFiles) items")
                     Spacer()
                     Text("\(formatBytes(progress.bytesCopied)) / \(formatBytes(progress.totalBytes))")
                 }
                 .font(.caption)
                 .monospacedDigit()
                 .foregroundStyle(.secondary)
             }
             .padding()
             .background(.regularMaterial)
             .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .top)
             .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Subviews

struct LeftPanelView: View {
    let root: FileNode?
    let diffOnly: Bool
    @EnvironmentObject var viewModel: CompareViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Left")
                .font(.callout.smallCaps())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.primary.opacity(0.05)), alignment: .bottom)
            
            if let root = root {
                TreeView(root: root, diffOnly: diffOnly, side: .left, searchText: viewModel.searchText)
                    .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView("Empty", systemImage: "folder")
            }
        }
        .background(.background)
    }
}

struct RightPanelView: View {
    let root: FileNode?
    let diffOnly: Bool
    @EnvironmentObject var viewModel: CompareViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Right")
                .font(.callout.smallCaps())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial) 
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.primary.opacity(0.05)), alignment: .bottom)
            
            if let root = root {
                TreeView(root: root, diffOnly: diffOnly, side: .right, searchText: viewModel.searchText)
                    .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView("Empty", systemImage: "folder")
            }
        }
        .background(.background)
    }
}

struct UnifiedPanelView: View {
    let root: FileNode?
    let diffOnly: Bool
    @EnvironmentObject var viewModel: CompareViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Unified Diff")
                .font(.callout.smallCaps())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.primary.opacity(0.05)), alignment: .bottom)
            
            if let root = root {
                TreeView(root: root, diffOnly: diffOnly, side: nil, searchText: viewModel.searchText)
                    .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView("Empty", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background(.background)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.pulse, isActive: true)
                .padding(.bottom, 10)
            
            VStack(spacing: 6) {
                Text("Interactive Folder Diff")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Made with ❤️ in Berlin")
                    .font(.body)
                
                Text("nginxdev")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            Link(destination: URL(string: "https://github.com/nginxdev")!) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("github.com/nginxdev")
                }
            }
            .buttonStyle(.link)
            .padding(.top, 4)
            
            Button("Close") {
                dismiss()
            }
            .controlSize(.large)
            .padding(.top, 20)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 350)
        .background(.ultraThinMaterial)
    }
}
