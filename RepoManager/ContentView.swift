//
//  ContentView.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = RepoListViewModel()
    @State private var isShowingCommitAlert = false
    @State private var commitMessage = ""
    @State private var isShowingForceAlert = false
    
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\GitRepo.name)]
    
    var filteredRepos: [GitRepo] {
        if searchText.isEmpty {
            return viewModel.repos
        } else {
            return viewModel.repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Table(filteredRepos, selection: $viewModel.selection, sortOrder: $sortOrder) {
                TableColumn("仓库名称", value: \.name) { repo in
                    RepoNameCell(repo: repo)
                }
                .width(min: 150)
                
                // [新增] 最新 Tag 列
                TableColumn("Tag", value: \.latestTag) { repo in
                    Text(repo.latestTag)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .width(max: 100)
                
                TableColumn("分支", value: \.branch) { repo in
                    Text(repo.branch).font(.system(.body, design: .monospaced))
                }
                
                TableColumn("状态", value: \.statusType) { repo in
                    StatusBadge(type: repo.statusType, message: repo.statusMessage)
                }
                
                TableColumn("操作") { repo in
                    RepoActionCell(
                        repo: repo,
                        viewModel: viewModel,
                        isShowingCommitAlert: $isShowingCommitAlert,
                        commitMessage: $commitMessage,
                        isShowingForceAlert: $isShowingForceAlert
                    )
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索仓库名称...")
            .onChange(of: sortOrder) { newOrder in viewModel.sort(using: newOrder) }
            .dropDestination(for: URL.self) { items, location in
                Task { await viewModel.handleDrop(urls: items) }
                return true
            }
            // [修改] 右键菜单移到 Table 层级，针对 Selection 生效
            // 这使得整行点击都有效
            .contextMenu(forSelectionType: GitRepo.ID.self) { selectedIds in
                // 获取当前右键选中的单个或多个 ID
                // 通常只对“第一个选中项”或“所有选中项”进行操作
                // 这里我们提供通用操作，以及针对单个项目的特定操作
                if let firstId = selectedIds.first, let repo = viewModel.repos.first(where: { $0.id == firstId }) {
                    
                    // --- 针对特定项目的操作 ---
                    
                    // 1. [新增] 打开 Xcode 项目 (如果有)
                    if let projectURL = repo.projectFileURL {
                        Button {
                            NSWorkspace.shared.open(projectURL)
                        } label: {
                            Text("Open Project in Xcode")
                            Image(systemName: "hammer") // 或 "app.badge"
                        }
                        Divider()
                    }
                    
                    // 2. 打开文件夹
                    Button {
                        let url = URL(fileURLWithPath: repo.path)
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Open in Finder")
                        Image(systemName: "folder")
                    }
                    
                    // 3. 在 Finder 中显示
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
                    } label: {
                        Text("Reveal in Finder")
                        Image(systemName: "magnifyingglass")
                    }
                    
                    // 4. 打开终端
                    Button {
                        let url = URL(fileURLWithPath: repo.path)
                        if let terminalUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                             NSWorkspace.shared.open([url], withApplicationAt: terminalUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        }
                    } label: {
                        Text("Open in Terminal")
                        Image(systemName: "terminal")
                    }
                    
                    Divider()
                    
                    // 5. 复制路径
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(repo.path, forType: .string)
                    } label: {
                        Text("Copy Path")
                        Image(systemName: "doc.on.doc")
                    }
                    
                    Divider()
                }
                
                // --- 针对所有选中的通用操作 ---
                Button("刷新选中 (\(selectedIds.count))") {
                    Task {
                        for id in selectedIds {
                            await viewModel.refreshSingle(id: id)
                        }
                    }
                }
            }
            
            BottomBarView(
                viewModel: viewModel,
                filteredCount: filteredRepos.count,
                filteredIds: filteredRepos.map { $0.id },
                isShowingCommitAlert: $isShowingCommitAlert,
                commitMessage: $commitMessage,
                isShowingForceAlert: $isShowingForceAlert
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await viewModel.refreshAll()
            viewModel.sort(using: sortOrder)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addRepo) { Label("添加仓库", systemImage: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.refreshAll(); viewModel.sort(using: sortOrder) } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .sheet(isPresented: $isShowingCommitAlert) {
            CommitSheet(
                message: $commitMessage,
                isPresented: $isShowingCommitAlert,
                onCommit: { msg, push in
                    await viewModel.batchCommitAndPush(message: msg, shouldPush: push)
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingImportSheet) {
            ImportSheetView(viewModel: viewModel)
        }
        .alert("确认强制同步？", isPresented: $isShowingForceAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                Task { await viewModel.batchOperation { _ = await GitService.forceSync(repo: $0) } }
            }
        } message: {
            Text("此操作不可逆，将丢失所有本地未提交修改。")
        }
    }
    
    func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        if panel.runModal() == .OK {
            for url in panel.urls {
                viewModel.addRepo(url: url)
            }
        }
    }
}

// 4. 顺便把底部栏也提取出来（可选，但推荐）
struct BottomBarView: View {
    @ObservedObject var viewModel: RepoListViewModel
    let filteredCount: Int
    let filteredIds: [UUID]
    @Binding var isShowingCommitAlert: Bool
    @Binding var commitMessage: String
    @Binding var isShowingForceAlert: Bool
    
    var body: some View {
        HStack {
            Button("全选/反选") {
                if viewModel.selection.count == filteredCount {
                    viewModel.selection.removeAll()
                } else {
                    viewModel.selection = Set(filteredIds)
                }
            }
            Text("已选: \(viewModel.selection.count)").foregroundColor(.secondary)
            if viewModel.isRefreshing {
                ProgressView().controlSize(.small).padding(.leading, 8)
            }
            Spacer()
            Group {
                Button("批量提交") {
                    commitMessage = ""
                    isShowingCommitAlert = true
                }
                .disabled(viewModel.selection.isEmpty)
                Button("批量同步") {
                    Task { await viewModel.batchOperation { _ = await GitService.sync(repo: $0) } }
                }
                .disabled(viewModel.selection.isEmpty)
                Button("强制同步") {
                    isShowingForceAlert = true
                }
                .foregroundColor(.red)
                .disabled(viewModel.selection.isEmpty)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}


struct StatusBadge: View {
    let type: RepoStatusType
    let message: String
    
    var color: Color {
        switch type {
        case .clean: return .green
        case .dirty: return .yellow
        case .ahead: return .blue
        case .behind: return .purple
        case .detached: return .orange // [新增] 游离状态使用橙色，提示警告
        case .diverged: return .orange
        case .error: return .red
        case .loading: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // 如果是 detached，可以用空心圆或者不同图标来区分，这里简单使用实心圆
            Circle().fill(color).frame(width: 8, height: 8)
            
            Text(message)
                .font(.caption)
                .foregroundColor(type == .clean ? .secondary : .primary)
                // 如果是 Detached 状态，可以加粗提示
                .fontWeight(type == .detached ? .medium : .regular)
        }
    }
}
