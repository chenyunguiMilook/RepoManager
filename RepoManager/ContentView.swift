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
    
    // 弹窗状态
    @State private var isShowingCommitAlert = false
    @State private var commitMessage = ""
    @State private var isShowingForceAlert = false
    @State private var isShowingSettings = false // 新增：控制设置弹窗
    
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
                
                // [已移除] TableColumn("操作")
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索仓库名称...")
            .onChange(of: sortOrder) { newOrder in viewModel.sort(using: newOrder) }
            .dropDestination(for: URL.self) { items, location in
                Task { await viewModel.handleDrop(urls: items) }
                return true
            }
            // MARK: - 右键菜单 (批量操作 + 详情)
            .contextMenu(forSelectionType: GitRepo.ID.self) { selectedIds in
                // 1. 核心 Git 操作区 (针对所有选中项)
                Section("批量操作 (\(selectedIds.count))") {
                    Button {
                        // 触发提交弹窗 (CommitSheet 会读取 viewModel.selection)
                        // 注意：这里需要确保 viewModel.selection 包含了 selectedIds
                        // 默认 SwiftUI Table 右键时会自动更新 selection，但手动同步一下更安全
                        if !selectedIds.isEmpty {
                            viewModel.selection = selectedIds
                            commitMessage = ""
                            isShowingCommitAlert = true
                        }
                    } label: {
                        Label("提交...", systemImage: "arrow.up.circle")
                    }
                    
                    Button {
                        Task {
                            // 临时保存 selection，防止异步过程中 UI 变化
                            let targetIds = selectedIds
                            // 既然没有 selection Binding 传入 batchOperation，
                            // 我们需要确保 VM 操作的是这些 ID。
                            // 简单做法：临时更新 VM selection，或者给 VM 加一个针对特定 IDs 的方法。
                            // 这里假设 VM.batchOperation 总是操作 viewModel.selection。
                            // 所以要在主线程先更新 selection
                            viewModel.selection = targetIds
                            await viewModel.batchOperation { await GitService.pull(repo: $0) }
                        }
                    } label: {
                        Label("拉取 (Pull)", systemImage: "arrow.down")
                    }
                    
                    Button {
                        Task {
                            let targetIds = selectedIds
                            viewModel.selection = targetIds
                            await viewModel.batchOperation { _ = await GitService.push(repo: $0) }
                        }
                    } label: {
                        Label("推送 (Push)", systemImage: "arrow.up")
                    }
                }
                
                Divider()
                
                // 2. 单项详情操作 (仅当选中单个，或者针对第一个选中项显示)
                if let firstId = selectedIds.first, let repo = viewModel.repos.first(where: { $0.id == firstId }) {
                    Section(repo.name) {
                        if let projectURL = repo.projectFileURL {
                            Button {
                                NSWorkspace.shared.open(projectURL)
                            } label: {
                                Label("Open Project in Xcode", systemImage: "hammer")
                            }
                        }
                        
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                        }
                        
                        Button {
                            if let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)], withApplicationAt: term, configuration: .init(), completionHandler: nil)
                            }
                        } label: {
                            Label("Open in Terminal", systemImage: "terminal")
                        }
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(repo.path, forType: .string)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            
            // 底部栏
            BottomBarView(
                viewModel: viewModel,
                filteredCount: filteredRepos.count,
                filteredIds: filteredRepos.map { $0.id },
                isShowingSettings: $isShowingSettings // 传递设置绑定
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
        // 弹窗层
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
        // 设置弹窗 (macOS 14 也可以用 SettingsLink，这里用 Sheet 简单模拟或调用系统设置)
        // 这里演示用 Sheet 打开 SettingsView，或者直接发送系统 Action
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .frame(width: 450, height: 250)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { isShowingSettings = false }
                    }
                }
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
    
    // 控制设置弹窗
    @Binding var isShowingSettings: Bool
    
    var body: some View {
        HStack {
            // 左侧：全选与计数
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
                Text("处理中...").font(.caption).foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 右侧：设置按钮 (Menu)
            Menu {
                Button {
                    // 方法1: 打开应用内设置 View
                    isShowingSettings = true
                    
                    // 方法2: 如果你更喜欢原生偏好设置窗口行为
                    // NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("偏好设置...", systemImage: "gear")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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
