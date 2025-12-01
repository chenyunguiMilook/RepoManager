//
//  RepoStatusType.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

// MARK: - Enums & Models

import Foundation

// 状态枚举：符合 Codable 和 Sendable
enum RepoStatusType: String, Codable, Sendable {
    case loading = "加载中..."
    case clean = "Synced"
    case dirty = "Dirty"
    case ahead = "Ahead"
    case behind = "Behind"
    case diverged = "Diverged"
    case error = "Error/Conflict"
}

// 仓库模型：核心数据结构，符合 Sendable
struct GitRepo: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let path: String
    let name: String
    
    // 运行时状态 (不参与 Hash/Equatable 以避免无关的 UI 重绘，但在 Swift 中 Struct 默认全属性参与)
    // 这里我们将状态作为 var，更新时替换整个 Struct
    var branch: String = "-"
    var statusType: RepoStatusType = .loading
    var statusMessage: String = ""
    
    init(id: UUID = UUID(), path: String, name: String) {
        self.id = id
        self.path = path
        self.name = name
    }
    
    // 自定义 CodingKeys，只持久化基本信息，不持久化状态
    enum CodingKeys: String, CodingKey {
        case id, path, name
    }
}

