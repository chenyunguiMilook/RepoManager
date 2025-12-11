# RepoManager — Copilot 指南

以下说明旨在帮助 AI 编码助手快速上手并在本代码库中安全、有效地提交更改。内容基于可在仓库中发现的实现与约定。

核心架构（大局）
- UI: `RepoManager/RepoManager/ContentView.swift` 是 SwiftUI 主视图，表格 + 底部栏驱动主要交互。
- 状态与业务逻辑: `RepoListViewModel` (`RepoListViewModel.swift`) 为 @MainActor 的 ObservableObject，负责仓库列表的持久化、并发刷新、批量操作与导入流程。
- Git 操作: `GitService` (`GitService.swift`) 封装对命令行 `git` 的调用（`runCommand`、`fetchStatus`、`commit`、`push` 等）。它使用 `nonisolated` 函数以便在后台线程执行。
- 启动与集成: `AppStartManager` 管理登录项（ServiceManagement），`RepoManagerApp.swift` 配置主窗口、菜单栏项与设置。

必须注意的项目约定与模式
- 线程与 Actor:
  - ViewModel 标注 `@MainActor`；对 UI 的更新应在 MainActor 上进行。
  - `GitService` 使用 `nonisolated` 以便从后台调用。重写或新增异步工具函数时，遵循现有的 `nonisolated` vs `@MainActor` 分界。
- 并发模式:
  - 使用 `Task.detached` 和 `withTaskGroup` 进行后台并发扫描/刷新（见 `RepoListViewModel.refreshAll()`）。保留 `currentOperation` 字段以避免覆盖并发中用户触发的状态。
- 持久化:
  - 仓库列表保存在 Application Support 下的 `GitHubble/repos.json`（见 `RepoListViewModel.savePath`）。修改数据模型需兼容 JSON 编解码。
- Git 路径与环境:
  - `GitService.runCommand` 默认使用 `/usr/bin/git`。在 CI 或不同用户环境中，`git` 可位于 `/usr/local/bin/git` 或需通过 `/usr/bin/env git` 调用；对路径敏感的改动需保留注释并提供回退方案。
- 本地工具集成:
  - 项目会尝试调用外部工具：`stree`（SourceTree 命令行）、`open`、`NSWorkspace` 与 `SMAppService`。新增集成时，请提供优雅降级（检测路径/Bundle ID 后再调用）。

典型开发/调试命令
- 打开工程（推荐 Xcode）：
  - `open RepoManager/RepoManager.xcodeproj` 或直接在 Xcode 中打开 `RepoManager.xcodeproj`。
- 命令行构建（无签名/仅本地构建验证）：
  - 构建: `xcodebuild -project RepoManager.xcodeproj -scheme RepoManager -configuration Debug build`
  - 测试: `xcodebuild test -project RepoManager.xcodeproj -scheme RepoManager -destination 'platform=macOS'`
  - 注意：CI/打包时可能需要工作区、签名与正确 scheme，优先使用 Xcode 运行以避免签名问题。

项目中常见代码片段与说明（可直接引用）
- 获取仓库状态并判断 branch/dirty/ahead/behind: `GitService.fetchStatus(for:)` — 若你修改分支状态逻辑，请保留对 `statusType` 与 `statusMessage` 的兼容写法。
- 批量操作模式: `RepoListViewModel.batchOperation(label:action:)` — 首先设置每个选中项的 `currentOperation`，并在后台执行后回到主线程清理并刷新对应仓库条目。
- 导入流程: `handleDrop(urls:)` 会尝试判断是否为 Git 仓库或扫描一级子目录，导入候选者会使用 `myProjectList` 优先选中常用项目名。

修改/添加规则（仅修改可被测试/运行的代码）
- 在对异步/并发代码做修改前，确保遵循 Actor 隔离（不要在非 MainActor 线程直接修改 `@Published` 属性）。
- 修改 `GitService.runCommand` 时保留对输出与 exit code 的返回约定 `(output: String, exitCode: Int32)`，以便现有调用方无需改动。
- 如果新增持久化字段，请同步更新 JSON 编解码器与 `loadFromDisk`/`saveToDisk`。

重要文件参考（快速索引）
- `RepoManager/RepoManager/GitService.swift` — Git CLI 封装与扫描逻辑
- `RepoManager/RepoManager/RepoListViewModel.swift` — 核心业务：刷新、批量操作、持久化、导入
- `RepoManager/RepoManager/ContentView.swift` — 主 UI、右键菜单、工具栏、拖放与辅助函数（openInBrowser/openInSourceTree）
- `RepoManager/RepoManager/RepoManagerApp.swift` — Scene/menus/settings/StatusBarExtra
- `RepoManager/RepoManager/Version+Behavior.swift` — 版本号解析与递增策略（用于 `calculateNextVersion`）

如果内容有遗漏或你希望我补充：请指出希望更详细的部分（例如 CI 流程、特定接口说明或更多代码示例）。

---
请审阅此草案并告诉我需要补充或精简的部分。准备根据反馈迭代。 
