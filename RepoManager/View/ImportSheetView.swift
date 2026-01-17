//
//  ImportSheetView.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

import SwiftUI

// --- 新增：导入确认视图 ---
struct ImportSheetView: View {
    @ObservedObject var viewModel: RepoListViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发现 Git 仓库").font(.headline)
            Text("拖入的文件夹中包含以下 Git 仓库，请选择要导入的项目：")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 列表区域
            List {
                ForEach($viewModel.importCandidates) { $candidate in
                    HStack {
                        Toggle(isOn: $candidate.isSelected) {
                            Text(candidate.name)
                                .fontWeight(.medium)
                        }
                        .toggleStyle(.checkbox)
                        
                        Spacer()
                        
                        Text(candidate.url.path)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 400)
            .border(Color(NSColor.separatorColor), width: 1)
            
            // 底部按钮
            HStack {
                Button("全选/反选") {
                    viewModel.toggleCandidateSelection()
                }
                
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("导入选中的仓库 (\(viewModel.importCandidates.filter(\.isSelected).count))") {
                    viewModel.confirmImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.importCandidates.filter(\.isSelected).isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}
