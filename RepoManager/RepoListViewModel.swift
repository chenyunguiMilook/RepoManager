//
//  RepoListViewModel.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


import SwiftUI
import Combine

// 待导入的候选仓库模型
struct ImportCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var isSelected: Bool = true // 默认选中
    
    var name: String { url.lastPathComponent }
}

@MainActor
final class RepoListViewModel: ObservableObject {
    @Published var repos: [GitRepo] = []
    @Published var selection: Set<GitRepo.ID> = []
    @Published var isRefreshing: Bool = false
    
    // --- 新增：导入弹窗相关状态 ---
    @Published var isShowingImportSheet: Bool = false
    @Published var importCandidates: [ImportCandidate] = []
    
    private let savePath: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("GitHubble")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("repos.json")
    }()
    
    init() {
        loadFromDisk()
        // 注意：这里不要调用 refreshAll()，否则启动时会卡 UI。
        // 交给 View 的 .task { } 去触发
    }
    
    // 核心逻辑：添加仓库（避免重复）
    func addRepo(url: URL) {
        let path = url.path
        let name = url.lastPathComponent
        guard !repos.contains(where: { $0.path == path }) else { return }
        
        let newRepo = GitRepo(path: path, name: name)
        repos.append(newRepo)
        saveToDisk() // 保存
        
        // 触发刷新
        Task { await refreshSingle(id: newRepo.id) }
    }
    
    // --- 新增：处理拖拽逻辑 ---
    func handleDrop(urls: [URL]) async {
        var candidatesFound: [ImportCandidate] = []
        
        // 切到后台线程进行文件 IO 操作
        await Task.detached(priority: .userInitiated) {
            for url in urls {
                // 1. 如果本身就是 Git 仓库，直接在 MainActor 添加（稍后处理）
                if GitService.isGitRepo(at: url) {
                    await MainActor.run {
                        self.addRepo(url: url)
                    }
                } else {
                    // 2. 否则扫描子目录
                    let subRepos = GitService.scanSubfolders(at: url)
                    let candidates = subRepos.map { ImportCandidate(url: $0) }
                    candidatesFound.append(contentsOf: candidates)
                }
            }
        }.value
        
        // 如果发现了子仓库，显示弹窗
        if !candidatesFound.isEmpty {
            // 过滤掉已经在列表中的仓库
            let existingPaths = Set(self.repos.map { $0.path })
            let newCandidates = candidatesFound.filter { !existingPaths.contains($0.url.path) }
            
            if !newCandidates.isEmpty {
                self.importCandidates = newCandidates
                self.isShowingImportSheet = true
            }
        }
    }
    
    // 确认导入选中的候选者
    func confirmImport() {
        for candidate in importCandidates where candidate.isSelected {
            addRepo(url: candidate.url)
        }
        importCandidates.removeAll()
        isShowingImportSheet = false
    }
    
    // 候选列表全选/反选
    func toggleCandidateSelection() {
        let allSelected = importCandidates.allSatisfy { $0.isSelected }
        for i in 0..<importCandidates.count {
            importCandidates[i].isSelected = !allSelected
        }
    }

    // MARK: - Persistence
    func loadFromDisk() {
        guard let data = try? Data(contentsOf: savePath),
              let savedRepos = try? JSONDecoder().decode([GitRepo].self, from: data) else { return }
        self.repos = savedRepos
    }
    
    func saveToDisk() {
        if let data = try? JSONEncoder().encode(repos) {
            try? data.write(to: savePath)
        }
    }
        
    // MARK: - Async Operations
    
    func refreshSingle(id: UUID) async {
        guard let index = repos.firstIndex(where: { $0.id == id }) else { return }
        // 标记该行为加载中
        repos[index].statusType = .loading
        let currentRepo = repos[index]
        
        // 切到后台线程执行
        let updatedRepo = await Task.detached(priority: .userInitiated) {
            return await GitService.fetchStatus(for: currentRepo)
        }.value
        
        // 回到 MainActor 更新 UI
        if let idx = repos.firstIndex(where: { $0.id == id }) {
            repos[idx] = updatedRepo
        }
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        // 创建 currentRepos 的副本以传给 detached task (GitRepo 是 Struct，Sendable)
        let currentRepos = self.repos
        
        // 使用 Stream 模式，处理完一个就回传一个，而不是等所有做完才刷新
        let repoUpdates = await Task.detached(priority: .userInitiated) { () -> [(UUID, GitRepo)] in
            // 注意：这里我们使用 TaskGroup 并发运行，但并不一次性返回所有
            // 实际上为了更好的 UX，我们更希望产生一个 AsyncStream，
            // 但为了简化代码，这里演示批量并发获取，然后一次性推回或者分批推回。
            // 既然 GitService 是 nonisolated，这里直接并发调用即可。
            
            return await withTaskGroup(of: (UUID, GitRepo).self) { group in
                for repo in currentRepos {
                    group.addTask {
                        let updated = await GitService.fetchStatus(for: repo)
                        return (repo.id, updated)
                    }
                }
                
                var results: [(UUID, GitRepo)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }.value
        
        // 等待所有结果（或者改为 AsyncStream 逐个 yield 回来以获得更好视觉效果）
        let results = await repoUpdates
        
        // 批量更新 UI
        for (id, updatedRepo) in results {
            if let index = repos.firstIndex(where: { $0.id == id }) {
                repos[index] = updatedRepo
            }
        }
    }
    
    func batchOperation(action: @escaping @Sendable (GitRepo) async -> Void) async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        let selectedRepos = repos.filter { selection.contains($0.id) }
        
        await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for repo in selectedRepos {
                    group.addTask {
                        await action(repo)
                    }
                }
            }
        }.value
        
        await refreshAll()
    }
    
    func toggleSelectAll() {
        if selection.count == repos.count {
            selection.removeAll()
        } else {
            selection = Set(repos.map { $0.id })
        }
    }
}
