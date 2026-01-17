//
//  CommitSheet.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/2.
//

import SwiftUI

// MARK: - 增强版 CommitSheet
struct CommitSheet: View {
    @Binding var message: String
    @Binding var isPresented: Bool
    
    // 回调现在是 async 的，并且接受 push 参数
    var onCommit: (String, Bool) async -> Void
    
    @State private var shouldPush: Bool = true // 默认选中
    @State private var isWorking: Bool = false
    @State private var progressText: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            if isWorking {
                // 进度展示状态
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在处理中...")
                        .font(.headline)
                    Text(shouldPush ? "正在提交并推送..." : "正在提交...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 300, height: 150)
            } else {
                // 正常输入状态
                Text("提交变更").font(.headline)
                
                TextField("Message", text: $message)
                    .frame(width: 300)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("提交后推送到远程 (Push)", isOn: $shouldPush)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .frame(width: 300, alignment: .leading)
                
                HStack {
                    Button("取消") {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("提交") {
                        startCommitProcess()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding()
        // 禁止在工作时通过点击背景关闭 (macOS sheet 默认行为通常不关闭，但可以防万一)
        .interactiveDismissDisabled(isWorking)
    }
    
    private func startCommitProcess() {
        isWorking = true
        Task {
            // 执行传入的异步闭包
            await onCommit(message, shouldPush)
            
            // 执行完毕后，UI 稍作停顿或直接关闭
            // 这里为了平滑体验，稍微 delay 一下让用户感觉到“完成”
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            await MainActor.run {
                isWorking = false
                isPresented = false
            }
        }
    }
}
