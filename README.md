# RepoManager

一个用于集中管理本地 Git 仓库状态的小工具（macOS）。支持查看分支/Tag/同步状态、批量 Pull/Push、右键快捷操作、拖拽导入等。

## 安装

使用 Homebrew 安装（你提供的方式）：

```sh
brew install --cask chenyunguiMilook/homebrew-tap/repomanager
```

安装完成后可在“应用程序 (Applications)”中找到并启动。

## 使用

- 打开应用后，搜索框会自动聚焦，直接输入即可过滤仓库。
- 支持拖拽文件夹到列表以导入仓库（会扫描一级子目录的 Git 仓库）。
- 右键仓库可执行常用操作：
  - Open in VSCode
  - 清理 `.build`
  - Open in Finder/Terminal/Xcode/SourceTree

## 从源码构建（可选）

```sh
open RepoManager/RepoManager.xcodeproj
```

或命令行构建：

```sh
xcodebuild -project RepoManager.xcodeproj -scheme RepoManager -configuration Debug build
```
