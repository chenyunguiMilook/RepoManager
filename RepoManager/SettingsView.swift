//
//  SettingsView.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


import SwiftUI

struct SettingsView: View {
    @StateObject private var startManager = AppStartManager.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 250) // 设定一个标准的固定大小
    }
}

struct GeneralSettingsView: View {
    @StateObject private var startManager = AppStartManager.shared
    
    var body: some View {
        VStack(spacing: 25) {
            // 顶部图标区
            VStack(spacing: 8) {
                Image(systemName: "network.badge.shield.half.filled") // 这里可以用你的 AppIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                
                Text("Repo Manager")
                    .font(.headline)
            }
            .padding(.top, 20)
            
            Divider()
            
            // 选项区
            HStack(alignment: .top, spacing: 20) {
                Text("启动:")
                    .frame(width: 80, alignment: .trailing) // 对齐标签
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("登录时打开", isOn: Binding(
                        get: { startManager.isEnabled },
                        set: { newValue in
                            startManager.toggleStartAtLogin(newValue)
                        }
                    ))
                    .toggleStyle(.checkbox) // macOS 上 Checkbox 样式更自然
                    
                    Text("开启后，应用将在您登录 macOS 时自动在后台运行。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}
