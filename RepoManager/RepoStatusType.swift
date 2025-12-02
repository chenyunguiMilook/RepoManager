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
    case detached = "Detached" // [新增]
    case diverged = "Diverged"
    case error = "Error/Conflict"
    
    // 排序优先级：越小越靠前
    private var sortPriority: Int {
        switch self {
        case .error: return 0      // 红色：错误
        case .detached: return 1   // [新增] 橙/灰色：游离状态，高风险
        case .diverged: return 2   // 橙色：分叉
        case .dirty: return 3      // 黄色：未提交
        case .behind: return 4     // 紫色：需拉取
        case .ahead: return 5      // 蓝色：需推送
        case .clean: return 6      // 绿色：正常
        case .loading: return 7    // 灰色
        }
    }
    
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

