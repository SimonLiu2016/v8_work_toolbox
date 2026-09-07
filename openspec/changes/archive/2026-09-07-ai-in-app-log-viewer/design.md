## Context

当前系统中的 `AiLogger` 是一个静态工具类，仅将结构化报文输出到 `debugPrint`。为了在应用内提供可视化观察器，需要将其改造为支持内存环形缓冲和响应式通知的基础组件，并设计专用的 UI 模态对话框 `AiLogDialog`。

## Goals / Non-Goals

**Goals:**
- 定义结构化 `AiLogEntry` 模型，准确记录时间戳、日志类型（Request / Response / Warning / Error）、供应商、协议、端点、状态码、耗时和内容摘要。
- 改造 `AiLogger`，在内存中维护最多 200 条的环形队列，并通过 `ValueNotifier<List<AiLogEntry>>` 实现低开销的 UI 响应式订阅。
- 开发 `AiLogDialog` 模态弹窗，提供暗黑控制台风格的高亮卡片流、单条展开、一键复制全部日志和清空功能。
- 在 `SmartDiskSlimmerPage` 和 `AiConfigPage` 暴露直观的入口按钮。

**Non-Goals:**
- 将日志持久化到本地 SQLite 或文件系统（保持内存轻量级，随应用关闭自动释放）。
- 实现复杂的正则过滤搜索（仅通过色彩与图标直观区分请求、响应与警告）。

## Decisions

### 决策 1: 使用 `ValueNotifier<List<AiLogEntry>>` 进行状态广播
- **选择**: `ValueNotifier` + 不可变列表更新。
- **理由**: 原生集成 Flutter 的 `ValueListenableBuilder`，无需引入复杂的状态管理或第三方 Stream 依赖，弹窗打开时即刻获取当前日志快照，关闭时自动解绑，生命周期清晰。
- **替代方案**: `StreamController.broadcast()`。缺点是重入或多组件监听时需手动管理 subscription，且不易直接获取最新快照。

### 决策 2: 采用居中模态弹窗 (`AiLogDialog`)
- **选择**: `showDialog(context, builder: ...)` 模态弹窗（宽度 720px，高度 520px）。
- **理由**: macOS 桌面端应用中，模态弹窗边界清晰，能从任意页面（瘦身页、配置页）统一调用，不会割裂底层页面的布局。

### 决策 3: 限制单条日志载荷大小与队列容量
- **选择**: 队列上限 200 条，超限 FIFO 淘汰；单条日志详情限制最大 4KB。
- **理由**: 防止超大 Prompt 或大量并发请求导致应用占用过多内存。

## Risks / Trade-offs

- **[风险] 频繁打印导致 UI 列表频繁重绘**
  - *缓解措施*: `diagnoseBatch` 本身已实施 800ms 步频，调用频率天然受控；同时 `ListView.builder` 仅渲染可见区域卡片，保证极致流畅。
- **[风险] 剪贴板复制过大内容造成卡顿**
  - *缓解措施*: 复制全部日志时只拼接结构化核心摘要，并提示 Toast 反馈。
