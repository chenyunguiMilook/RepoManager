//
//  RepoListViewModel.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


import SwiftUI
import Combine

@MainActor
final class RepoListViewModel: ObservableObject {
    @Published var repos: [GitRepo] = []
    @Published var selection: Set<GitRepo.ID> = []
    @Published var isRefreshing: Bool = false
    
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
    
    func addRepo(url: URL) {
        let path = url.path
        let name = url.lastPathComponent
        guard !repos.contains(where: { $0.path == path }) else { return }
        
        let newRepo = GitRepo(path: path, name: name)
        repos.append(newRepo)
        saveToDisk()
        
        Task { await refreshSingle(id: newRepo.id) }
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
