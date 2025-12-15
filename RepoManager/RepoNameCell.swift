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
    init(repo: GitRepo) {
        self.repo = repo
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(repo.name).font(.headline)
            Text(repo.path).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
