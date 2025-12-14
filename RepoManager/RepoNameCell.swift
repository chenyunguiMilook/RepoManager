//
//  RepoNameCell.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//


import SwiftUI
import Foundation

struct RepoNameCell: View {
    let repo: GitRepo
    let onDoubleClick: (() -> Void)?

    init(repo: GitRepo, onDoubleClick: (() -> Void)? = nil) {
        self.repo = repo
        self.onDoubleClick = onDoubleClick
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(repo.name).font(.headline)
            Text(repo.path).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // 移除 .contentShape 和 .onTapGesture，让 Table 原生处理选择
        // 双击功能移至 ContentView 的 Table 层级处理
    }
}
