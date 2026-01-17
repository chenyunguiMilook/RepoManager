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
    let onTogglePin: (() -> Void)?

    init(repo: GitRepo, onTogglePin: (() -> Void)? = nil) {
        self.repo = repo
        self.onTogglePin = onTogglePin
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                onTogglePin?()
            } label: {
                Image(systemName: repo.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(repo.isPinned ? "Unpin" : "Pin")

            VStack(alignment: .leading) {
                Text(repo.name).font(.headline)
                Text(repo.path).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
