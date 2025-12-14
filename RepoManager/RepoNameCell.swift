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
        // 让整块区域都可点击（否则双击只能点到文字附近）
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick?()
        }
        // 注意：这里不要加 contextMenu，
        // 因为现在由 Table 的 contextMenu(forSelectionType:) 接管
    }
}
