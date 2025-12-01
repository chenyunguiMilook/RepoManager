//
//  RepoStatusType.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

// MARK: - Enums & Models

import Foundation

// 状态枚举：符合 Codable 和 Sendable
enum RepoStatusType: String, Codable, Sendable {
    case loading = "加载中..."
    case clean = "Synced"
    case dirty = "Dirty"
    case ahead = "Ahead"
    case behind = "Behind"
    case diverged = "Diverged"
    case error = "Error/Conflict"
}

// 仓库模型：核心数据结构，符合 Sendable
struct GitRepo: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let path: String
    let name: String
    
    // 运行时状态 (不参与 Hash/Equatable 以避免无关的 UI 重绘，但在 Swift 中 Struct 默认全属性参与)
    // 这里我们将状态作为 var，更新时替换整个 Struct
    var branch: String = "-"
    var statusType: RepoStatusType = .loading
    var statusMessage: String = ""
    
    init(id: UUID = UUID(), path: String, name: String) {
        self.id = id
        self.path = path
        self.name = name
    }
    
    // 自定义 CodingKeys，只持久化基本信息，不持久化状态
    enum CodingKeys: String, CodingKey {
        case id, path, name
    }
}

// MARK: - Git Service Helper
import Foundation

struct GitService {
    
    // nonisolated 关键字明确告诉 Swift 6：此函数不依赖当前 Actor (MainActor)，
    // 可以在任意后台线程池中运行。
    nonisolated static func runCommand(_ arguments: [String], at path: String) async -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: path)
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // 读取数据可能耗时，放在后台处理
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
        
        // 1. 获取分支
        let (branchOut, _) = await runCommand(["rev-parse", "--abbrev-ref", "HEAD"], at: path)
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
