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
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(repo.name).font(.headline)
            Text(repo.path).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        // 修改点 1: 强制让这个 VStack 填满表格列的宽度
        .frame(maxWidth: .infinity, alignment: .leading)
        // 修改点 2: 将整个区域（包括空白处）定义为可交互区域
        .contentShape(Rectangle())
        // 修改点 3: ContextMenu 必须放在 contentShape 之后
        .contextMenu {
            // 1. 打开文件夹
            Button {
                let url = URL(fileURLWithPath: repo.path)
                NSWorkspace.shared.open(url)
            } label: {
                Text("Open in Finder")
                Image(systemName: "folder")
            }
            
            // 2. 在 Finder 中显示
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
            } label: {
                Text("Reveal in Finder")
                Image(systemName: "magnifyingglass")
            }
            
            Divider()
            
            // 3. 打开终端
            Button {
                let url = URL(fileURLWithPath: repo.path)
                let terminalUrl = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: terminalUrl,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            } label: {
                Text("Open in Terminal")
                Image(systemName: "terminal")
            }
            
            Divider()
            
            // 4. 复制路径
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(repo.path, forType: .string)
            } label: {
                Text("Copy Path")
                Image(systemName: "doc.on.doc")
            }
        }
    }
}
