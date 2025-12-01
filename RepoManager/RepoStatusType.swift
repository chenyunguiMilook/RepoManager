//
//  RepoStatusType.swift
//  RepoManager
//
//  Created by chenyungui on 2025/12/1.
//

// MARK: - Enums & Models

import Foundation

// 1. 让枚举遵循 Comparable
enum RepoStatusType: String, Codable, Sendable, Comparable {
    case loading = "加载中..."
    case clean = "Synced"
    case ahead = "Ahead"
    case behind = "Behind"
    case dirty = "Dirty"
    case diverged = "Diverged"
    case error = "Error/Conflict"
    
    // 2. 定义排序优先级 (数字越小排越前，或者反过来，取决于 Comparable 实现)
    // 这里我们定义：问题越严重，优先级越高 (值越小)
    private var sortPriority: Int {
        switch self {
        case .error: return 0      // 红色：最严重
        case .diverged: return 1   // 橙色：严重
        case .dirty: return 2      // 黄色：需注意
        case .behind: return 3     // 紫色：需拉取
        case .ahead: return 4      // 蓝色：需推送
        case .clean: return 5      // 绿色：正常
        case .loading: return 6    // 灰色：未知
        }
    }
    
    // 3. 实现 Comparable 协议
    static func < (lhs: RepoStatusType, rhs: RepoStatusType) -> Bool {
        return lhs.sortPriority < rhs.sortPriority
    }
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

