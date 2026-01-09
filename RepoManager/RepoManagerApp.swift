//
//  RepoManagerApp.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI
import Carbon.HIToolbox

@main
struct RepoManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 1. 获取打开窗口的环境变量
    @Environment(\.openWindow) private var openWindow
    @AppStorage(WindowPositioningController.autoHideEnabledDefaultsKey) private var isAutoHideMainWindowEnabled: Bool = true

    var body: some Scene {
        // 2. 给主窗口组指定一个唯一的 ID
        Window("Repo Manager", id: "MainWindow") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .background(WindowAccessor { window in
                    WindowPositioningController.shared.registerMainWindow(window)
                })
                .task {
                    // Bridge SwiftUI's openWindow into the controller so hotkey can recreate the window.
                    WindowPositioningController.shared.openMainWindow = {
                        openWindow(id: "MainWindow")
                    }
                }
        }
        // 移除标准菜单中的 "新建窗口" 选项，防止通过 Cmd+N 创建窗口
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(replacing: .appSettings) {
                Button("偏好设置...") {
                    isAutoHideMainWindowEnabled = false
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            SidebarCommands()
        }
        .windowResizability(.contentSize)

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

            Toggle("自动隐藏主窗口", isOn: $isAutoHideMainWindowEnabled)

            Divider()
            
            Button("偏好设置...") {
                isAutoHideMainWindowEnabled = false
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            // 菜单项 2: 退出应用
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    private(set) var hotKeyManager = HotKeyManager()
    private var hotKeySettings: HotKeySettings?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 初始化快捷键设置
        hotKeySettings = HotKeySettings.shared
        
        hotKeyManager.onHotKey = {
            Task { @MainActor in
                WindowPositioningController.shared.showMainWindowUnderMouse()
            }
        }
        
        // 用保存的设置注册快捷键
        if let settings = hotKeySettings {
            hotKeyManager.register(keyCode: settings.keyCode, modifiers: settings.modifiers)
            
            // 监听快捷键设置变化，动态更新
            settingsObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HotKeySettingsDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                if let settings = self?.hotKeySettings {
                    self?.hotKeyManager.reregister(with: settings)
                }
            }
        }
    }
    
    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
