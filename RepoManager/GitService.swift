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

    nonisolated static func fetchStatus(for repo: GitRepo) async -> GitRepo {
        var newRepo = repo
        let path = repo.path
        
        // 1. 探测项目文件
        newRepo.projectFileURL = detectProjectFile(at: path)
        
        // 2. 获取最新 Tag
        let (tagOut, tagCode) = await runCommand(["describe", "--tags", "--abbrev=0"], at: path)
        newRepo.latestTag = (tagCode == 0 && !tagOut.isEmpty) ? tagOut : "-"
        
        // [新增] 判断最新 Tag 是否就在当前 HEAD 上
        if newRepo.latestTag != "-" {
            // 获取 HEAD 的完整 Hash
            let (headHash, _) = await runCommand(["rev-parse", "HEAD"], at: path)
            // 获取该 Tag 指向的完整 Hash
            let (tagHash, _) = await runCommand(["rev-list", "-n", "1", newRepo.latestTag], at: path)
            
            // 如果两者 Hash 相同且不为空，说明当前提交就是这个版本的发布点
            if !headHash.isEmpty && headHash == tagHash {
                newRepo.isTagAtHead = true
            } else {
                newRepo.isTagAtHead = false
            }
        } else {
            newRepo.isTagAtHead = false
        }
        
        // 3. 获取分支状态 (保持不变)
        let (branchOut, _) = await runCommand(["rev-parse", "--abbrev-ref", "HEAD"], at: path)
        
        if branchOut == "HEAD" {
            let (hashOut, _) = await runCommand(["rev-parse", "--short", "HEAD"], at: path)
            newRepo.branch = "HEAD (\(hashOut))"
            newRepo.statusType = .detached
            newRepo.statusMessage = "游离状态"
            let (statusOut, _) = await runCommand(["status", "--porcelain"], at: path)
            if !statusOut.isEmpty { newRepo.statusMessage = "游离且未提交" }
            return newRepo
        }
        
        newRepo.branch = branchOut.isEmpty ? "Unknown" : branchOut
        
        // Fetch & Check Dirty
        _ = await runCommand(["fetch"], at: path)
        
        let (statusOut, _) = await runCommand(["status", "--porcelain"], at: path)
        if !statusOut.isEmpty {
            newRepo.statusType = .dirty
            newRepo.statusMessage = "未提交变更"
            return newRepo
        }
        
        // Check Ahead/Behind
        let (countOut, code) = await runCommand(["rev-list", "--left-right", "--count", "HEAD...@{u}"], at: path)
        if code == 0 {
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
            }
        } else {
            newRepo.statusType = .clean
            newRepo.statusMessage = "已同步"
        }
        
        return newRepo
    }
    
    nonisolated static func detectProjectFile(at pathStr: String) -> URL? {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: pathStr)
        
        // 1. 检查 *.xcodeproj
        // 由于 xcodeproj 是目录，我们需要扫描
        if let contents = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            if let xcodeProj = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
                return xcodeProj
            }
        }
        
        // 2. 检查 Package.swift
        let packageURL = rootURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageURL.path) {
            return packageURL
        }
        
        return nil
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

    nonisolated static func pull(repo: GitRepo) async -> Bool {
        // 使用 --rebase 保持提交历史整洁，如果不需要可去掉
        let (_, code) = await runCommand(["pull", "--rebase"], at: repo.path)
        return code == 0
    }
    
    nonisolated static func sync(repo: GitRepo) async -> Bool {
        if await pull(repo: repo) {
            return await push(repo: repo)
        }
        return false
    }

    nonisolated static func forceSync(repo: GitRepo) async -> Bool {
        _ = await runCommand(["fetch", "--all"], at: repo.path)
        let (_, code) = await runCommand(["reset", "--hard", "origin/\(repo.branch)"], at: repo.path)
        return code == 0
    }
    
    nonisolated static func createTag(repo: GitRepo, version: String) async -> Bool {
        // 1. 本地打标签
        let (_, tagCode) = await runCommand(["tag", version], at: repo.path)
        if tagCode != 0 { return false }
        
        // 2. 推送到远程
        let (_, pushCode) = await runCommand(["push", "origin", version], at: repo.path)
        return pushCode == 0
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
