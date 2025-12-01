//
//  RepoActionCell.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI

struct RepoActionCell: View {
    let repo: GitRepo
    @ObservedObject var viewModel: RepoListViewModel
    
    // 我们需要通过 Binding 或 Closure 通知父视图显示弹窗
    @Binding var isShowingCommitAlert: Bool
    @Binding var commitMessage: String
    @Binding var isShowingForceAlert: Bool
    
    var body: some View {
        HStack {
            // 提交
            Button {
                viewModel.selection = [repo.id]
                commitMessage = ""
                isShowingCommitAlert = true
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .disabled(repo.statusType != .dirty)
            .help("提交变更")
            
            // 同步
            Button {
                Task {
                    await viewModel.batchOperation { _ = await GitService.sync(repo: $0) }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("同步")
            
            // 强制
            Button {
                // 强制同步通常只针对当前这个，这里稍微简化，也走批量逻辑但只选一个
                viewModel.selection = [repo.id] 
                isShowingForceAlert = true
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundColor(.red)
            }
            .help("强制覆盖")
        }
        .buttonStyle(.plain)
    }
}
