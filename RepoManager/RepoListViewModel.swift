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
    
    func batchCommitAndPush(message: String, shouldPush: Bool) async {
        // UI 进入 loading 状态
        isRefreshing = true
        defer { isRefreshing = false }
        
        let selectedRepos = repos.filter { selection.contains($0.id) }
        
        // 后台并发执行
        await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for repo in selectedRepos {
                    group.addTask {
                        // 1. Commit
                        if repo.statusType == .dirty {
                            let commitSuccess = await GitService.commit(repo: repo, message: message)
                            
                            // 2. Push (if enabled and commit succeeded or was clean)
                            if shouldPush && commitSuccess {
                                _ = await GitService.push(repo: repo)
                            }
                        } else if shouldPush {
                            // 如果本来就是 clean 或者 ahead，直接尝试 push
                            _ = await GitService.push(repo: repo)
                        }
                    }
                }
            }
        }.value
        
        // 全部完成后刷新状态
        await refreshAll()
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
    
    /// 计算仓库的建议下一个版本
    func calculateNextVersion(for repo: GitRepo) -> String {
        let currentTag = repo.latestTag
        // 尝试解析当前 Tag，如果失败 (比如是 "-" 或空)，则默认为 0.0.0
        let currentVersion = Version(string: currentTag) ?? Version(0, 0, 0)
        
        // 使用 Version+Behavior 中的 nextVersion 方法
        let next = currentVersion.nextVersion()
        return next.description
    }
    
    /// 创建标签并刷新
    func createTagAndRefresh(for repo: GitRepo, version: String) async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // 在后台执行
        let success = await Task.detached {
            return await GitService.createTag(repo: repo, version: version)
        }.value
        
        if success {
            print("Tag \(version) created successfully for \(repo.name)")
        } else {
            print("Failed to create tag \(version)")
        }
        
        // 刷新该仓库状态
        await refreshSingle(id: repo.id)
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
