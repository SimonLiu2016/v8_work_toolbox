## Context

参见 `proposal.md - Why`。当前 ArgoCD 监控页的布局在实机验证中暴露三个问题，全部是纯 UI 层。

## Goals / Non-Goals

**Goals:**
- 环境标签 + 详情卡 → 单行条，左信息右操作。
- 表头字号从 caption 提到 bodySecondary。
- 列宽从全 FixedColumnWidth 改为 Flex + Intrinsic 混用。

**Non-Goals:**
- 不改数据层、GitLab 客户端、路径统一、凭据存储。
- 不改其他 Tab（连接配置 / 项目管理 / 批量操作）。

## Decisions

### 1. 合并环境条：把 `_envChip` 和详情卡合为一个 widget

当前结构是两个独立区块：
- `_envChip`：名字 + Switch + ✕（选中靠点击名字）
- 详情卡：模式徽章 + 编辑按钮 + GitLab URL / 路径 / 频率 / 状态

合并后 `_envChip` 直接包含全部信息，不再有单独的详情卡：

```
┌─ 环境条（选中时背景色 accentSubtle）──────────────────────┐
│ 左：[名字] [模式徽章]  GitLab: … / 路径: … / 频率: …     │
│ 右：[编辑环境] ◯── ✕                                    │
└──────────────────────────────────────────────────────────┘
```

实现：`_envChip` 内部用 `Row`，左段 `Expanded(Column(...))` 放名称+徽章+信息概要，右段固定放按钮+Switch+✕。多环境仍用 `Wrap`。

### 2. 表头字号

`AppTheme.fontCaption` → `AppTheme.fontBodySecondary`。caption 约 11-12px 在深色背景上确实偏小。

### 3. 列宽弹性

```dart
columnWidths: const {
  0: FlexColumnWidth(2),       // 项目名
  1: FlexColumnWidth(2),       // 当前 Tag
  2: FlexColumnWidth(2),       // 目标 Tag
  3: IntrinsicColumnWidth(),   // 关闭弹窗提醒（checkbox + label）
  4: IntrinsicColumnWidth(),   // 状态（pill）
  5: IntrinsicColumnWidth(),   // 启用（switch）
},
```

三个文字列按 2:2:2 弹性分配剩余宽度，三个按钮/开关列贴合内容。窗口宽时文字列展开，窄时收缩。移除 `IntrinsicWidth`（上一轮已删，确认不再引入）。

## Risks / Trade-offs

- **[Risk] 合并后环境条信息密集，窄窗口可能换行**
  → Mitigation: 信息概要用 `Text(overflow: ellipsis)`，窄时截断而非溢出。

- **[Risk] FlexColumnWidth 在 0 行时 Table 高度为 0**
  → 无影响：空态已有 `_tags.isEmpty` 分支返回居中提示，不走到 Table。

## Migration Plan

1. 改 `_envChip` 合并详情信息。
2. 删除独立的详情卡 `Container` 块。
3. 改表头字号与列宽。
4. `flutter analyze` 保持 0 errors / 0 warnings。
5. 构建部署，实机确认：单行条 + 列宽缩放 + 表头可读。
