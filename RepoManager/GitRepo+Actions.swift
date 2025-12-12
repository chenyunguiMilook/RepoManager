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
        let path = self.path
        let fm = FileManager.default
        let codeCLI = "/usr/local/bin/code"

        if fm.fileExists(atPath: codeCLI) {
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: codeCLI)
                task.arguments = [path]
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
            task.arguments = ["code", path]
            try task.run()
            return
        } catch {
            // 继续回退到 App 打开
        }

        // 回退：按 bundle id 打开 VSCode 或使用 open -a
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCodeInsiders") {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appUrl, configuration: .init(), completionHandler: nil)
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Visual Studio Code", path]
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
