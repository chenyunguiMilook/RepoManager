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
            // 表格现在非常简洁
            Table(filteredRepos, selection: $viewModel.selection, sortOrder: $sortOrder) {
                
                // 列1：使用提取的 Cell
                TableColumn("仓库名称", value: \.name) { repo in
                    RepoNameCell(repo: repo)
                }
                .width(min: 150)
                
                // 列2
                TableColumn("分支", value: \.branch) { repo in
                    Text(repo.branch).font(.system(.body, design: .monospaced))
                }
                
                // 列3
                TableColumn("状态", value: \.statusType) { repo in
                    StatusBadge(type: repo.statusType, message: repo.statusMessage)
                }
                
                // 列4：使用提取的 Cell
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
            
            // 底部栏
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
                // 这里传入异步闭包，View 会等待它完成
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
