//
//  ContentView.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let focusRepoSearchField = Notification.Name("RepoManager.focusRepoSearchField")
}

struct ContentView: View {
    @StateObject private var viewModel = RepoListViewModel()
    
    // 弹窗状态
    @State private var isShowingCommitAlert = false
    @State private var commitMessage = ""
    @State private var isShowingForceAlert = false
    @State private var isShowingSettings = false // 新增：控制设置弹窗
    // [新增] 版本控制弹窗状态
    @State private var isShowingVersionSheet = false
    @State private var targetVersion = ""
    @State private var selectedRepoForVersion: GitRepo? = nil

    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\GitRepo.name)]
    @FocusState private var isSearchFocused: Bool
    
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
                    RepoNameCell(repo: repo) {
                        viewModel.togglePin(id: repo.id)
                    }
                }
                .width(min: 150)
                
                TableColumn("分支", value: \.branch) { repo in
                    Text(repo.branch)
                        .font(.system(.body, design: .monospaced))
                }
                
                TableColumn("Tag", value: \.latestTag) { repo in
                    Text(repo.latestTag)
                        .font(.system(.body, design: .monospaced))
                        // 如果当前 HEAD 就是 Tag，显示绿色；否则（有新提交）显示灰色
                        .foregroundColor(repo.isTagAtHead ? .green : .secondary)
                }
                .width(max: 100)

                // [修改] 状态列：优先显示 active operation
                TableColumn("状态", value: \.statusType) { repo in
                    if let operation = repo.currentOperation {
                        // 显示活动指示器
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text(operation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // 显示静态状态
                        StatusBadge(type: repo.statusType, message: repo.statusMessage)
                    }
                }

                // [新增] 快捷打开列：点击图标即可用对应应用打开
                TableColumn("打开") { repo in
                    HStack(spacing: 8) {
                        Button {
                            if let projectURL = repo.projectFileURL {
                                NSWorkspace.shared.open(projectURL)
                            }
                        } label: {
                            Image(systemName: "hammer")
                        }
                        .help("Open Project in Xcode")
                        .disabled(repo.projectFileURL == nil)

                        Button {
                            repo.openInVSCode()
                        } label: {
                            Image(systemName: "chevron.left.slash.chevron.right")
                        }
                        .help("Open in VS Code")

                        Button {
                            if let terminalApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)], withApplicationAt: terminalApp, configuration: .init(), completionHandler: nil)
                            }
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .help("Open in Terminal")

                        Button {
                            openInSourceTree(path: repo.path)
                        } label: {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        .help("Open in SourceTree")

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Open in Finder")

                        Button {
                            openInBrowser(remoteURL: repo.remoteURL)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .help("Open in Browser")
                        .disabled(repo.remoteURL.isEmpty)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .width(min: 120, ideal: 140)
                
                // [已移除] TableColumn("操作")
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索仓库名称...")
            .searchFocused($isSearchFocused)
            .onChange(of: isSearchFocused) { focused in
                if focused {
                    InputSourceManager.switchToEnglish()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusRepoSearchField)) { _ in
                isSearchFocused = true
            }
            .onChange(of: sortOrder) { newOrder in viewModel.sort(using: newOrder) }
            .dropDestination(for: URL.self) { items, location in
                Task { await viewModel.handleDrop(urls: items) }
                return true
            }
            // MARK: - 右键菜单 (批量操作 + 详情)
            .contextMenu(forSelectionType: GitRepo.ID.self) { selectedIds in
                // 1. Git 批量操作
                Section("Git 操作") {
                    Button {
                        if !selectedIds.isEmpty {
                            viewModel.selection = selectedIds
                            commitMessage = ""
                            isShowingCommitAlert = true
                        }
                    } label: { Label("提交...", systemImage: "arrow.up.circle") }
                    
                    Button {
                        Task {
                            viewModel.selection = selectedIds
                            await viewModel.batchOperation(label: "Pulling") {
                                await GitService.pull(repo: $0)
                            }
                        }
                    } label: { Label("拉取 (Pull)", systemImage: "arrow.down") }
                    
                    Button {
                        Task {
                            viewModel.selection = selectedIds
                            await viewModel.batchOperation(label: "Pushing") {
                                _ = await GitService.push(repo: $0)
                            }
                        }
                    } label: { Label("推送 (Push)", systemImage: "arrow.up") }
                }
                
                Divider()
                
                // 2. 单项详情操作 (仅当选中单个，或者针对第一个选中项显示)
                if let firstId = selectedIds.first, let repo = viewModel.repos.first(where: { $0.id == firstId }) {
                                    
                    // [新增] 版本递增操作
                    Button {
                        selectedRepoForVersion = repo
                        targetVersion = viewModel.calculateNextVersion(for: repo)
                        isShowingVersionSheet = true
                    } label: {
                        Label("递增版本...", systemImage: "tag")
                    }
                    .disabled(repo.isTagAtHead) // [关键修改] 如果 Tag 在 HEAD 上，禁用此功能
                    
                    // [新增] SPM 复制与浏览器打开
                    if !repo.remoteURL.isEmpty {
                        Divider()
                        
                        // Copy SPM Dependency
                        Button {
                            // 格式: .package(url: "git@github.com...", from: "0.0.18"),
                            let tag = (repo.latestTag == "-" || repo.latestTag.isEmpty) ? "0.0.1" : repo.latestTag
                            let spmString = ".package(url: \"\(repo.remoteURL)\", from: \"\(tag)\"),"
                            
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(spmString, forType: .string)
                        } label: {
                            Label("Copy SPM Dependency", systemImage: "swift")
                        }
                        
                        // Open in Browser
                        Button {
                            openInBrowser(remoteURL: repo.remoteURL)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                    }
                    Divider()
                    
                    Section(repo.name) {
                        Button {
                            viewModel.togglePin(id: repo.id)
                        } label: {
                            Label(repo.isPinned ? "Unpin" : "Pin", systemImage: repo.isPinned ? "pin.slash" : "pin")
                        }

                        Button {
                            openInSourceTree(path: repo.path)
                        } label: {
                            Label("Open in SourceTree", systemImage: "arrow.triangle.branch")
                        }
                        if let projectURL = repo.projectFileURL {
                            Button { NSWorkspace.shared.open(projectURL) } label: { Label("Open Project in Xcode", systemImage: "hammer") }
                        }
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: repo.path)) } label: { Label("Open in Finder", systemImage: "folder") }
                        Button {
                            if let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)], withApplicationAt: term, configuration: .init(), completionHandler: nil)
                            }
                        } label: { Label("Open in Terminal", systemImage: "terminal") }
                        
                        Button {
                            repo.openInVSCode()
                        } label: { Label("Open in VSCode", systemImage: "chevron.left.slash.chevron.right") }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(repo.path, forType: .string)
                        } label: { Label("Copy Path", systemImage: "doc.on.doc") }
                        
                        // 从列表中移除（仅从应用中移除，不删除磁盘）
                        Button(role: .destructive) {
                            viewModel.removeRepo(id: repo.id)
                        } label: {
                            Label("从列表移除", systemImage: "minus.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task {
                                await MainActor.run { viewModel.updateRepoOperation(id: repo.id, operation: "Cleaning .build...") }

                                let cleaned = await Task.detached { repo.cleanBuildDirectory() }.value
                                if !cleaned {
                                    // 失败时可在将来扩展为显示 Alert
                                    print("clean .build failed for: \(repo.path)")
                                }

                                await MainActor.run {
                                    viewModel.updateRepoOperation(id: repo.id, operation: nil)
                                    Task { await viewModel.refreshSingle(id: repo.id) }
                                }
                            }
                        } label: {
                            Label("清理 .build", systemImage: "trash")
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
            // 窗口打开时自动聚焦搜索框，立即可输入
            await MainActor.run {
                isSearchFocused = true
            }
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
        // [新增] Version Sheet
        .sheet(isPresented: $isShowingVersionSheet) {
            VersionSheet(
                version: $targetVersion,
                isPresented: $isShowingVersionSheet,
                repoName: selectedRepoForVersion?.name ?? "",
                onConfirm: { version in
                    if let repo = selectedRepoForVersion {
                        await viewModel.createTagAndRefresh(for: repo, version: version)
                    }
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
    
    // [辅助函数] 将 Git URL (SSH/HTTPS) 转换为浏览器可打开的 URL
    func openInBrowser(remoteURL: String) {
        // 输入: git@github.com:User/Repo.git 或 https://github.com/User/Repo.git
        // 目标: https://github.com/User/Repo
        
        var urlStr = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 去掉 .git 后缀
        if urlStr.hasSuffix(".git") {
            urlStr = String(urlStr.dropLast(4))
        }
        
        // 2. 处理 SSH 协议 (git@github.com:User/Repo)
        if urlStr.hasPrefix("git@") {
            // 去掉 "git@"
            let hostAndPath = urlStr.dropFirst(4) // github.com:User/Repo
            // 将第一个 ":" 替换为 "/" -> github.com/User/Repo
            if let colonRange = hostAndPath.range(of: ":") {
                let host = hostAndPath[..<colonRange.lowerBound]
                let path = hostAndPath[colonRange.upperBound...]
                urlStr = "https://\(host)/\(path)"
            }
        }
        
        // 3. 确保是 HTTPS
        if !urlStr.hasPrefix("http") {
             // 如果没转换成功，可能是 ssh:// 开头，或者其他格式
             // 这里简单处理，如果还不是 http，就强制加 https
             if !urlStr.hasPrefix("https://") {
                 // 避免双重 https
                 urlStr = "https://" + urlStr
             }
        }
        
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // [新增] 打开 SourceTree 的逻辑
    func openInSourceTree(path: String) {
        let repoURL = URL(fileURLWithPath: path)
        
        // 1. 尝试使用命令行工具 `stree` (通常安装在 /usr/local/bin/stree)
        let streePath = "/usr/local/bin/stree"
        if FileManager.default.fileExists(atPath: streePath) {
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: streePath)
                task.arguments = [path]
                try task.run()
                return // 如果命令执行成功，直接返回
            } catch {
                print("Failed to run stree command: \(error)")
            }
        }
        
        // 2. 兜底方案：直接通过 NSWorkspace 查找并打开 SourceTree 应用程序
        // SourceTree 的 Bundle Identifier 通常是 com.torusknot.SourceTreeNotMAS
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.torusknot.SourceTreeNotMAS") {
            NSWorkspace.shared.open([repoURL], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else {
            // 3. 最后的尝试：直接用 `open` 命令打开应用
            // 这对那些安装在非标准路径但已注册的应用有效
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "SourceTree", path]
            try? task.run()
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
                    WindowPositioningController.shared.isAutoHideEnabled = false
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
