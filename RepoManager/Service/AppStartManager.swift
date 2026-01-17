//
//  AppStartManager.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


import Foundation
import ServiceManagement
import Combine

@MainActor
final class AppStartManager: ObservableObject {
    static let shared = AppStartManager()
    
    // 发布属性，用于驱动 UI 变化
    @Published var isEnabled: Bool = false
    
    private init() {
        // 初始化时检查当前状态
        self.checkStatus()
    }
    
    func checkStatus() {
        // .enabled 表示已注册为登录项
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    func toggleStartAtLogin(_ shouldEnable: Bool) {
        do {
            if shouldEnable {
                // 注册当前主应用为登录项
                try SMAppService.mainApp.register()
            } else {
                // 取消注册
                try SMAppService.mainApp.unregister()
            }
            // 更新状态
            self.isEnabled = shouldEnable
        } catch {
            print("修改开机自启失败: \(error)")
            // 如果失败，回滚 UI 状态
            self.isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
