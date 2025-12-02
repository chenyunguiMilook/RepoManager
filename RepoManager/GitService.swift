//
//  GitService.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


// MARK: - Git Service Helper
import Foundation

struct GitService {
    
    // nonisolated 关键字明确告诉 Swift 6：此函数不依赖当前 Actor (MainActor)，
    // 可以在任意后台线程池中运行。
    nonisolated static func runCommand(_ arguments: [String], at path: String) async -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        // 注意：这里需确保 git 路径正确，有些环境可能是 /usr/local/bin/git
        // 如果遇到问题，可以使用 "/usr/bin/env" 作为 executableURL，arguments 放 ["git", ...]
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: path)
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (output, task.terminationStatus)
        } catch {
            return ("Git execution failed: \(error.localizedDescription)", -1)
        }
    }

    // 计算属性完全在后台进行，返回一个新的 Sendable Repo 对象
    nonisolated static func fetchStatus(for repo: GitRepo) async -> GitRepo {
        var newRepo = repo
        let path = repo.path
        
        // 1. 获取分支名称
        // 如果是 Detached HEAD，git rev-parse --abbrev-ref HEAD 通常返回 "HEAD"
        let (branchOut, _) = await runCommand(["rev-parse", "--abbrev-ref", "HEAD"], at: path)
        
        // --- [新增] Detached HEAD 检测逻辑 ---
        if branchOut == "HEAD" {
            // 获取当前的短 Commit Hash
            let (hashOut, _) = await runCommand(["rev-parse", "--short", "HEAD"], at: path)
            newRepo.branch = "HEAD (\(hashOut))" // 显示为 HEAD (a1b2c3d)
            newRepo.statusType = .detached
            newRepo.statusMessage = "游离状态"
            
            // 游离状态下通常不需要检测 Ahead/Behind，因为没有默认的上游分支
            // 但我们仍然需要检查 Dirty 状态
            let (statusOut, _) = await runCommand(["status", "--porcelain"], at: path)
            if !statusOut.isEmpty {
                newRepo.statusMessage = "游离且未提交" // 组合提示
            }
            
            return newRepo
        }
        
        // 正常分支逻辑
        newRepo.branch = branchOut.isEmpty ? "Unknown" : branchOut
        
        // 2. Fetch
        _ = await runCommand(["fetch"], at: path)
        
        // 3. Check Dirty
        let (statusOut, _) = await runCommand(["status", "--porcelain"], at: path)
        if !statusOut.isEmpty {
            newRepo.statusType = .dirty
            newRepo.statusMessage = "未提交变更"
            return newRepo
        }
        
        // 4. Check Ahead/Behind
        let (countOut, code) = await runCommand(["rev-list", "--left-right", "--count", "HEAD...@{u}"], at: path)
        
        if code != 0 {
            newRepo.statusType = .error
            newRepo.statusMessage = "无上游/连接失败"
            return newRepo
        }
        
        let components = countOut.components(separatedBy: .whitespaces).compactMap { Int($0) }
        if components.count == 2 {
            let ahead = components[0]
            let behind = components[1]
            
            if ahead > 0 && behind > 0 {
                newRepo.statusType = .diverged
                newRepo.statusMessage = "分叉 (⬆️\(ahead) ⬇️\(behind))"
            } else if ahead > 0 {
                newRepo.statusType = .ahead
                newRepo.statusMessage = "需推送 (⬆️\(ahead))"
            } else if behind > 0 {
                newRepo.statusType = .behind
                newRepo.statusMessage = "需拉取 (⬇️\(behind))"
            } else {
                newRepo.statusType = .clean
                newRepo.statusMessage = "已同步"
            }
        } else {
            newRepo.statusType = .clean
            newRepo.statusMessage = "已同步"
        }
        
        return newRepo
    }
    
    // 动作类命令
    nonisolated static func commit(repo: GitRepo, message: String) async -> Bool {
        _ = await runCommand(["add", "."], at: repo.path)
        let (_, code) = await runCommand(["commit", "-m", message], at: repo.path)
        return code == 0
    }
    
    nonisolated static func push(repo: GitRepo) async -> Bool {
        let (_, code) = await runCommand(["push"], at: repo.path)
        return code == 0
    }

    nonisolated static func sync(repo: GitRepo) async -> Bool {
        let (_, pullCode) = await runCommand(["pull", "--rebase"], at: repo.path)
        if pullCode != 0 { return false }
        let (_, pushCode) = await runCommand(["push"], at: repo.path)
        return pushCode == 0
    }
    
    nonisolated static func forceSync(repo: GitRepo) async -> Bool {
        _ = await runCommand(["fetch", "--all"], at: repo.path)
        let (_, code) = await runCommand(["reset", "--hard", "origin/\(repo.branch)"], at: repo.path)
        return code == 0
    }
}

extension GitService {
    // 检查是否为 Git 仓库 (检查是否存在 .git 子目录)
    // nonisolated 确保不阻塞主线程
    nonisolated static func isGitRepo(at url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    // 扫描指定文件夹的一级子目录，返回所有是 Git 仓库的 URL
    nonisolated static func scanSubfolders(at url: URL) -> [URL] {
        let fileManager = FileManager.default
        // 获取一级子目录内容，跳过隐藏文件
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var foundRepos: [URL] = []
        for folderURL in contents {
            // 简单判断是否是目录
            if (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if isGitRepo(at: folderURL) {
                    foundRepos.append(folderURL)
                }
            }
        }
        return foundRepos
    }
}
