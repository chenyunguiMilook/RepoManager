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
    var isSelected: Bool
    
    var name: String { url.lastPathComponent }
    
    // 增加初始化方法
    nonisolated init(url: URL, isSelected: Bool = true) {
        self.url = url
        self.isSelected = isSelected
    }
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
    
    func sort(using comparators: [KeyPathComparator<GitRepo>]) {
        // 使用 Swift 标准库的 sort 方法，传入 comparators
        repos.sort(using: comparators)
    }

    func handleDrop(urls: [URL]) async {
        var candidatesFound: [ImportCandidate] = []
        
        // 捕获静态列表以供后台线程使用 (Set是值类型，Sendable)
        let favoriteList = Self.myProjectList
        
        await Task.detached(priority: .userInitiated) {
            for url in urls {
                if GitService.isGitRepo(at: url) {
                    await MainActor.run { self.addRepo(url: url) }
                } else {
                    // 扫描子目录
                    let subRepos = GitService.scanSubfolders(at: url)
                    
                    // 映射逻辑：如果在 favoriteList 中，则 isSelected = true，否则 false
                    let candidates = subRepos.map { repoUrl -> ImportCandidate in
                        let name = repoUrl.lastPathComponent
                        let shouldSelect = favoriteList.contains(name)
                        return ImportCandidate(url: repoUrl, isSelected: shouldSelect)
                    }
                    candidatesFound.append(contentsOf: candidates)
                }
            }
        }.value
        
        if !candidatesFound.isEmpty {
            // 过滤已存在的
            let existingPaths = Set(self.repos.map { $0.path })
            let newCandidates = candidatesFound.filter { !existingPaths.contains($0.url.path) }
            
            if !newCandidates.isEmpty {
                // 排序优化：把选中的（你的项目）排在前面，方便查看
                self.importCandidates = newCandidates.sorted {
                    ($0.isSelected && !$1.isSelected) // true 排在 false 前面
                }
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
    
/// 更新指定 Repo 的操作状态 (UI 更新必须在 MainActor)
    func updateRepoOperation(id: UUID, operation: String?) {
        if let index = repos.firstIndex(where: { $0.id == id }) {
            repos[index].currentOperation = operation
        }
    }
    
    // MARK: - Async Operations
    
    func refreshSingle(id: UUID) async {
        guard let index = repos.firstIndex(where: { $0.id == id }) else { return }
        // 只有当没有其他操作时，才显示 Loading 状态，避免覆盖 "Pushing..."
        if repos[index].currentOperation == nil {
            repos[index].statusType = .loading
        }
        let currentRepo = repos[index]
        
        let updatedRepo = await Task.detached(priority: .userInitiated) {
            return await GitService.fetchStatus(for: currentRepo)
        }.value
        
        // 恢复时，保留原来的 currentOperation (如果它在 fetch 期间发生了变化)
        // 但通常 fetchStatus 完成后，我们直接覆盖即可，因为 fetch 本身就是一种 operation
        if let idx = repos.firstIndex(where: { $0.id == id }) {
            var finalRepo = updatedRepo
            // 保持当前的操作状态（如果有其他并发操作正在进行）
            finalRepo.currentOperation = repos[idx].currentOperation
            repos[idx] = finalRepo
        }
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        // 仅对没有正在进行操作的 Repo 显示 loading
        for i in 0..<repos.count {
            if repos[i].currentOperation == nil {
                repos[i].statusType = .loading
            }
        }
        
        let currentRepos = self.repos
        
        let repoUpdates = await Task.detached(priority: .userInitiated) { () -> [(UUID, GitRepo)] in
            return await withTaskGroup(of: (UUID, GitRepo).self) { group in
                for repo in currentRepos {
                    group.addTask {
                        let updated = await GitService.fetchStatus(for: repo)
                        return (repo.id, updated)
                    }
                }
                var results: [(UUID, GitRepo)] = []
                for await result in group { results.append(result) }
                return results
            }
        }.value
        
        for (id, updatedRepo) in repoUpdates {
            if let index = repos.firstIndex(where: { $0.id == id }) {
                // 如果此时用户触发了其他操作，不要覆盖 currentOperation
                var finalRepo = updatedRepo
                finalRepo.currentOperation = repos[index].currentOperation
                repos[index] = finalRepo
            }
        }
    }
    
    /// 通用批量操作，支持单独显示状态
    func batchOperation(label: String, action: @escaping @Sendable (GitRepo) async -> Void) async {
        // 全局 loading 稍微显示一下或者不显示，取决于设计，这里我们主要依赖行内 loading
        isRefreshing = true
        defer { isRefreshing = false }
        
        let selectedIds = selection
        
        // 1. 先将所有选中的 Repo 状态设为 "Pending..." 或具体操作名
        for id in selectedIds {
            updateRepoOperation(id: id, operation: label + "...")
        }
        
        let snapshotRepos = repos.filter { selectedIds.contains($0.id) }
        
        await withTaskGroup(of: Void.self) { group in
            for repo in snapshotRepos {
                group.addTask {
                    // 执行操作
                    await action(repo)
                    
                    // 操作完成后：
                    await MainActor.run {
                        // 1. 清除操作状态
                        self.updateRepoOperation(id: repo.id, operation: nil)
                        // 2. 刷新该 Repo 的 Git 状态
                        Task { await self.refreshSingle(id: repo.id) }
                    }
                }
            }
        }
    }
    
    /// 专门的提交并推送逻辑
    func batchCommitAndPush(message: String, shouldPush: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        let selectedIds = selection
        // 初始状态
        for id in selectedIds {
            updateRepoOperation(id: id, operation: "准备中...")
        }
        
        let snapshotRepos = repos.filter { selectedIds.contains($0.id) }
        
        await withTaskGroup(of: Void.self) { group in
            for repo in snapshotRepos {
                group.addTask {
                    // 1. Commit
                    await MainActor.run { self.updateRepoOperation(id: repo.id, operation: "Committing...") }
                    
                    var commitSuccess = false
                    if repo.statusType == .dirty {
                        commitSuccess = await GitService.commit(repo: repo, message: message)
                    } else {
                        // 如果不脏，视为 Commit 阶段通过（可能是单纯想 Push Ahead 的）
                        commitSuccess = true
                    }
                    
                    // 2. Push
                    if shouldPush && commitSuccess {
                        await MainActor.run { self.updateRepoOperation(id: repo.id, operation: "Pushing...") }
                        _ = await GitService.push(repo: repo)
                    }
                    
                    // 3. 完成
                    await MainActor.run {
                        self.updateRepoOperation(id: repo.id, operation: nil)
                        Task { await self.refreshSingle(id: repo.id) }
                    }
                }
            }
        }
    }
    
    // 创建 Tag
    func createTagAndRefresh(for repo: GitRepo, version: String) async {
        // 设置状态
        updateRepoOperation(id: repo.id, operation: "Tagging...")
        
        // 后台执行
        _ = await Task.detached {
            return await GitService.createTag(repo: repo, version: version)
        }.value
        
        // 恢复状态并刷新
        updateRepoOperation(id: repo.id, operation: nil)
        await refreshSingle(id: repo.id)
    }
    
    /// 计算仓库的建议下一个版本
    func calculateNextVersion(for repo: GitRepo) -> String {
        let currentTag = repo.latestTag
        // 尝试解析当前 Tag，如果失败 (比如是 "-" 或空)，则默认为 0.0.0
        let currentVersion = Version(string: currentTag) ?? Version(0, 0, 0)
        
        // 使用 Version+Behavior 中的 nextVersion 方法
        let next = currentVersion.nextVersion()
        return next.description
    }
    
    func toggleSelectAll() {
        if selection.count == repos.count {
            selection.removeAll()
        } else {
            selection = Set(repos.map { $0.id })
        }
    }
    
    // 使用 Set 提高查找性能
    private static let myProjectList: Set<String> = [
        "GuideKit",
        "PickerKit",
        "FillDisplayKit",
        "CoreComponent",
        "StyleKit",
        "TextInputKit",
        "ShortcutKit",
        "SVGView",
        "MetalCore",
        "LayerKit",
        "BitmapLayerKit",
        "PrimeKit",
        "RenderKit",
        "FillKit",
        "ShapeListKit",
        "ShapeDrawKit",
        "ShapeLayerKit",
        "TextLayerKit",
        "MetalShapeRender",
        "UndoKit",
        "NodeKit",
        "NodeListKit",
        "CodingKit",
        "MSDFGenSwift",
        "VectorShopDependencies",
        "AttributeTableKit",
        "ColorPicker",
        "CoreUI",
        "BezierKit",
        "CatalystUI",
        "MetalShaderCompiler",
        "MetalSharedTypes",
        "PathTesselator",
        "SnappingKit",
        "StringKit",
        "SwiftInit",
        "SwiftyXML",
        "Triangulation",
        "VisualDebugger"
    ]
}
