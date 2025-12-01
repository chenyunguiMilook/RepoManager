//
//  RepoManagerApp.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI

@main
struct RepoManagerApp: App {
    // 1. 获取打开窗口的环境变量
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 2. 给主窗口组指定一个唯一的 ID
        WindowGroup(id: "MainWindow") {
            ContentView()
                // 设置窗口最小尺寸，避免太小不好看
                .frame(minWidth: 800, minHeight: 500)
        }
        // 设置窗口默认标题
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
        }

        // macOS 会自动将 "Settings..." (偏好设置) 菜单项绑定到这里
        // 快捷键默认是 Cmd + ,
        Settings {
            SettingsView()
        }

        // 3. 添加菜单栏额外入口 (Status Bar Icon)
        MenuBarExtra("GitHubble", systemImage: "network") {
            // 菜单项 1: 打开/激活主窗口
            Button("打开主窗口") {
                // 强制打开 ID 为 MainWindow 的窗口
                // 即使窗口被 Cmd+W 关闭了，这行代码也能重新将其打开
                openWindow(id: "MainWindow")
                
                // 将应用置于最前 (获取焦点)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o") // 支持快捷键 Cmd+O
            
            Divider()
            
            // MARK: - 修改点：使用 SettingsLink
            // 注意：SettingsLink 仅支持 macOS 14.0+
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("偏好设置...")
                }
                .keyboardShortcut(",", modifiers: .command) // 绑定 Cmd+,
            } else {
                // macOS 13 或更低版本的兼容代码
                Button("偏好设置...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
            }
            
            Divider()
            
            // 菜单项 2: 退出应用
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
