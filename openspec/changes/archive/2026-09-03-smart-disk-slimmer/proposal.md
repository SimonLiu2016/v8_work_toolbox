## Why

用户的 macOS 设备磁盘空间常年被不可见的应用缓存、已卸载软件遗留数据、废弃工程产物以及编程语言/IDE 的多个历史版本所填满，且用户无法得知哪些目录可以安全删除、哪些属于已卸载软件、哪些属于特定开发框架。当前工具箱缺乏全盘透视与智能分析治理能力。通过构建分级扫描、多版本识别、原生废纸篓安全删除与 AI 智能研判相结合的系统瘦身模块，帮助用户清晰掌握磁盘占用全貌并安全释放巨额存储。

## What Changes

- **分级按需磁盘扫描体系**：
  - 阶段 1（瞬时定向，1-3秒）：快速扫描核心高发重灾区（Xcode DerivedData、系统缓存、下载归档包等），立竿见影呈现可清理项。
  - 阶段 2（多版本与开发环境矩阵）：探测 Python（pyenv/conda/系统）、Node.js（nvm/fnm）、Java（JDK/SDKMAN）及 JetBrains/Android Studio 历史升级遗留大版本，支持指定历史版本独立清理。
  - 阶段 3（深度孤立残留分析）：比对 `/Applications` 中已安装应用与 `~/Library`、`Containers` 下的散落目录，精准标出已卸载软件的“孤立残留”。
- **AI 智能批量与单项研判**：
  - 对置信度较低的未知深层大目录（无关联应用、特殊哈希命名），提取路径、扩展名、层级与时间戳等无敏感隐私的元数据，批量调用已配置的 `AiService` 进行智能风险评级与处置建议。
  - 在前端列表中提供单个条目的「🤖 让 AI 分析」即时诊断功能。
- **100% 原生废纸篓安全机制**：
  - 默认清理操作一律调用 macOS 原生 `NSWorkspace.shared.recycle` 将文件移至系统废纸篓，绝不执行物理强制删除，保障用户随时可通过快捷键 `⌘Z` 或在废纸篓中「放回原处」。
- **结构化可视化界面**：
  - 嵌入三栏导航体系（归入「系统与配置」分类），提供磁盘空间柱状透视、分级清理清单（已卸载残留、开发构建缓存、多版本管理、AI 研判项）、体积排序与清理成果报告。

## Capabilities

### New Capabilities
- `disk-analyzer`: 分级按需磁盘扫描引擎、已卸载应用孤立残留匹配、多版本运行时治理与 macOS 原生废纸篓安全回收通道。
- `ai-disk-diagnostics`: 基于 `AiService` 的磁盘未知项智能研判协议，支持批量低置信度打包诊断与单项深度会诊。

### Modified Capabilities

## Impact

- 原生层：在 `AppDelegate.swift` 中新增 `recycleFile` / `recycleFiles` 原生桥接通道（通过 `NSWorkspace.shared.recycle`）。
- 服务层：新增 `DiskScanService`（多级并发扫描、应用注册表比对、版本探测器）与 `AiDiskDiagnosticsService`（智能打包与诊断响应解析）。
- 工具注册：新增 `SmartDiskSlimmerToolDefinition`，接入 `ToolRegistry` 并挂载于「系统与配置」分类。
