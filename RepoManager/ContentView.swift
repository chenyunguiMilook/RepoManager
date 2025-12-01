//
//  ContentView.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RepoListViewModel()
    @State private var isShowingCommitAlert = false
    @State private var commitMessage = ""
    @State private var isShowingForceAlert = false
    
    // 1. 新增：搜索文本状态
    @State private var searchText = ""
    
    // 2. 新增：排序状态
    @State private var sortOrder = [KeyPathComparator(\GitRepo.name)]
    
    // 3. 新增：计算属性，用于过滤显示的数据
    // 逻辑：先过滤，后排序（因为 viewModel.repos 已经在 onChange 中被排过序了，这里只需过滤即可）
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
            // 4. 修改：数据源从 viewModel.repos 改为 filteredRepos
            Table(filteredRepos, selection: $viewModel.selection, sortOrder: $sortOrder) {
                
                TableColumn("仓库名称", value: \.name) { repo in
                    VStack(alignment: .leading) {
                        // 高亮搜索匹配文字 (可选优化，此处仅显示普通文字)
                        Text(repo.name).font(.headline)
                        Text(repo.path).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .width(min: 150)
                
                TableColumn("分支", value: \.branch) { repo in
                    Text(repo.branch)
                        .font(.system(.body, design: .monospaced))
                }
                
                TableColumn("状态", value: \.statusType) { repo in
                    StatusBadge(type: repo.statusType, message: repo.statusMessage)
                }
                
                TableColumn("操作") { repo in
                    HStack {
                        Button {
                            viewModel.selection = [repo.id]
                            commitMessage = ""
                            isShowingCommitAlert = true
                        } label: { Image(systemName: "arrow.up.circle") }
                        .disabled(repo.statusType != .dirty)
                        .help("提交变更")
                        
                        Button {
                            Task { await viewModel.batchOperation { _ = await GitService.sync(repo: $0) } }
                        } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .help("同步")
                        
                        Button {
                            Task { await viewModel.batchOperation { _ = await GitService.forceSync(repo: $0) } }
                        } label: { Image(systemName: "exclamationmark.arrow.circlepath").foregroundColor(.red) }
                        .help("强制覆盖")
                    }
                    .buttonStyle(.plain)
                }
            }
            // 5. 新增：搜索修饰符
            // placement: .toolbar 会自动将其放在 macOS 窗口右上角的标准位置
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索仓库名称...")
            // 4. 新增：监听排序变化
            .onChange(of: sortOrder) { newOrder in
                // 当用户点击表头时，newOrder 变了，触发 ViewModel 排序
                viewModel.sort(using: newOrder)
            }
            // --- 拖拽核心修改：支持拖入文件夹 ---
            .dropDestination(for: URL.self) { items, location in
                Task {
                    await viewModel.handleDrop(urls: items)
                }
                return true
            }
            // 底部栏
            HStack {
                Button("全选/反选") { viewModel.toggleSelectAll() }
                Text("已选: \(viewModel.selection.count)")
                    .foregroundColor(.secondary)
                
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.small).padding(.leading, 8)
                    Text("正在处理...").font(.caption).foregroundColor(.secondary)
                }
                
                Spacer()
                
                Group {
                    Button("批量提交") {
                        commitMessage = ""
                        isShowingCommitAlert = true
                    }
                    .disabled(viewModel.selection.isEmpty)
                    
                    Button("批量同步") {
                        Task {
                            await viewModel.batchOperation { repo in
                                _ = await GitService.sync(repo: repo)
                            }
                        }
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
        // 关键优化：视图加载后才开始拉取 Git 状态，避免启动卡顿
        .task {
            // 给 UI 0.5秒的时间先渲染出列表骨架，再开始重度 IO
            try? await Task.sleep(nanoseconds: 500_000_000)
            await viewModel.refreshAll()
            viewModel.sort(using: sortOrder)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addRepo) {
                    Label("添加仓库", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.refreshAll() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .sheet(isPresented: $isShowingCommitAlert) {
            VStack(spacing: 20) {
                Text("提交变更").font(.headline)
                TextField("Message", text: $commitMessage).frame(width: 300)
                HStack {
                    Button("取消") { isShowingCommitAlert = false }
                    Button("提交") {
                        isShowingCommitAlert = false
                        Task {
                            await viewModel.batchOperation { repo in
                                if repo.statusType == .dirty {
                                    _ = await GitService.commit(repo: repo, message: commitMessage)
                                }
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .alert("确认强制同步？", isPresented: $isShowingForceAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                Task {
                    await viewModel.batchOperation { repo in
                        _ = await GitService.forceSync(repo: repo)
                    }
                }
            }
        } message: {
            Text("此操作不可逆，将丢失所有本地未提交修改。")
        }
        .sheet(isPresented: $viewModel.isShowingImportSheet) {
            ImportSheetView(viewModel: viewModel)
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

struct StatusBadge: View {
    let type: RepoStatusType
    let message: String
    
    var color: Color {
        switch type {
        case .clean: return .green
        case .dirty: return .yellow
        case .ahead: return .blue
        case .behind: return .purple
        case .diverged: return .orange
        case .error: return .red
        case .loading: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(message).font(.caption)
                .foregroundColor(type == .clean ? .secondary : .primary)
        }
    }
}
