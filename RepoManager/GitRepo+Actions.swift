//
//  GitRepo+Actions.swift
//  RepoManager
//
//  自动生成：将与仓库路径相关的辅助操作封装到 `GitRepo` 扩展中。
//

import Foundation
import AppKit

extension GitRepo {
    /// 在 VSCode 中打开仓库路径：优先尝试 `code` CLI，其次尝试使用 app bundle 打开，最后使用 `open -a`。
    func openInVSCode() {
        let repoPath = self.path
        let fm = FileManager.default
        let codeCLI = "/usr/local/bin/code"

        // 如果仓库根目录下存在 .code-workspace，优先打开该 workspace
        let targetURL: URL = {
            let repoURL = URL(fileURLWithPath: repoPath)
            guard let entries = try? fm.contentsOfDirectory(at: repoURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return repoURL
            }
            let workspaces = entries
                .filter { $0.pathExtension == "code-workspace" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return workspaces.first ?? repoURL
        }()

        let targetPath = targetURL.path

        if fm.fileExists(atPath: codeCLI) {
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: codeCLI)
                task.arguments = [targetPath]
                try task.run()
                return
            } catch {
                print("Failed to run code CLI: \(error)")
            }
        }

        // 尝试使用 /usr/bin/env code
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["code", targetPath]
            try task.run()
            return
        } catch {
            // 继续回退到 App 打开
        }

        // 回退：按 bundle id 打开 VSCode 或使用 open -a
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([targetURL], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCodeInsiders") {
            NSWorkspace.shared.open([targetURL], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Visual Studio Code", targetPath]
            try? task.run()
        }
    }

    /// 在 Antigravity 中打开仓库路径：优先尝试 `agy` CLI，其次尝试使用 app bundle 打开，最后使用 `open -a`。
    func openInAntigravity() {
        let repoPath = self.path
        let fm = FileManager.default
        let antigravityCLI = "/Users/chenyungui/.antigravity/antigravity/bin/agy"

        if fm.fileExists(atPath: antigravityCLI) {
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: antigravityCLI)
                task.arguments = [repoPath]
                try task.run()
                return
            } catch {
                print("Failed to run antigravity CLI: \(error)")
            }
        }

        // 尝试使用 /usr/bin/env agy
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["agy", repoPath]
            try task.run()
            return
        } catch {
            // 继续回退到 App 打开
        }

        // 回退：按 bundle id 打开 Antigravity 或使用 open -a
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.antigravity.app") {
            NSWorkspace.shared.open([URL(fileURLWithPath: repoPath)], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Antigravity", repoPath]
            try? task.run()
        }
    }

    /// 删除仓库下的 `.build` 目录（如果存在）。返回是否成功（不存在视为成功）。
    @discardableResult
    func cleanBuildDirectory() -> Bool {
        let buildURL = URL(fileURLWithPath: path).appendingPathComponent(".build")
        let fm = FileManager.default
        if fm.fileExists(atPath: buildURL.path) {
            do {
                try fm.removeItem(at: buildURL)
                return true
            } catch {
                print("Failed to remove .build at \(buildURL.path): \(error)")
                return false
            }
        }
        // 不存在则视为成功
        return true
    }
}
