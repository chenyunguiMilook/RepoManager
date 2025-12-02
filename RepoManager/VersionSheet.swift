//
//  VersionSheet.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/2.
//

import SwiftUI

struct VersionSheet: View {
    @Binding var version: String
    @Binding var isPresented: Bool
    let repoName: String
    // 异步回调
    var onConfirm: (String) async -> Void
    
    @State private var isWorking: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            if isWorking {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.2)
                    Text("正在创建标签并推送...").font(.headline)
                }
                .frame(width: 300, height: 150)
            } else {
                Text("递增版本: \(repoName)").font(.headline)
                
                TextField("Version", text: $version)
                    .frame(width: 300)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Text("将在本地创建标签并推送到远程 (origin)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("发布") {
                        startProcess()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(version.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding()
        .interactiveDismissDisabled(isWorking)
    }
    
    private func startProcess() {
        isWorking = true
        Task {
            await onConfirm(version)
            try? await Task.sleep(nanoseconds: 200_000_000) // 短暂延迟以优化体验
            await MainActor.run {
                isWorking = false
                isPresented = false
            }
        }
    }
}
