## Context

在完成资产提示词预览与覆盖特性后，用户反馈全景母图编辑区存在弹窗空白灰屏、按钮图标重复与操作栏横向溢出问题。
参见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 修复 `AssetPromptPreviewDialog` 因 `Spacer()` 侵入 `AlertDialog.actions`（`OverflowBar`）所导致的 `ParentDataWidget` 异常，确保弹窗在 Release 模式下稳定正常显示。
- 净化 `series_page.dart` 中全景母图区域的按钮设计：去掉“生成 360° 全景母图”与“一键无损切片”上的重复图标/Emoji，精简文案去除冗余字样。
- 重构全景母图操作栏排版：将过长的切片说明文本下沉为副标题，操作按钮组支持自适应排列，彻底消除横向溢出。

**Non-Goals:**
- 不变更全景切片算法（`SphericalPerspectiveSlicer`）与底层的球面光线投射逻辑。
- 不变更资产卡数据模型结构与已实现的持久化字段。

## Decisions

### 1. 弹窗操作栏采用独立 Row 容器包裹
- **决策**：在 `AssetPromptPreviewDialog` 的 `actions` 中，使用单一 `SizedBox(width: double.infinity, child: Row(...))` 包裹内部按钮。
- **理由**：`AlertDialog.actions` 默认由 `OverflowBar` 承载，直接把 `Spacer()` 传给 `actions: [...]` 会导致 `Expanded` 无法绑定 `FlexParentData`。通过显式放入 `Row`，`Spacer()` 可以合法实现左侧“还原为默认组装”与右侧“取消 / 以此 Prompt 生成”的两端对齐，彻底消除构建期异常。

### 2. 按钮视觉降噪与文案精简
- **决策**：
  - “生成 360° 全景母图”按钮：移除 `Icon(Icons.auto_awesome)` 与 Emoji `✨`，移除后缀 `(1次API)`，精简为纯文本 `FilledButton`，文案为 `生成全景母图`（生成中显示进度指示器与 `生成中…`）。
  - “一键无损切片”按钮：移除 `Icon(Icons.crop_free)` 与 Emoji `🔄`，精简为 `OutlinedButton`，文案为 `一键切片`（切片中显示 `切片中…`）。
- **理由**：降低视觉噪点，提升桌面端专业质感，大幅压缩按钮宽度。

### 3. 说明文案与操作按钮分层解耦
- **决策**：将长说明文本 `（1次文生母图 · 本地毫秒级无损切片正/反/侧机位 · 彻底根除反打雷同）` 从标题行中剥离，作为标题下方浅灰小字副标题，或者在右侧操作区采用 `Wrap(spacing: 8, runSpacing: 6, ...)` 排布。
- **理由**：标题行仅保留区域标题与右侧操作按钮，确保即使窗口缩窄，按钮也不会溢出容器视口。

## Risks / Trade-offs

- [Risk] 操作按钮精简文案后，新用户可能不知道切片是在本地完成还是消耗 API → 在标题下方的副标题文字中明确说明“本地毫秒级无损提取各方位视角，无需消耗 API”，兼顾说明完整性与操作栏整洁度。
