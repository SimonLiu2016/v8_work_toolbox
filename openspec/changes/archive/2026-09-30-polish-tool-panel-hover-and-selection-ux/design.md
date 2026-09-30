## Context

参见 `proposal.md`。当前 `ToolPanel` 在展开状态下使用 `ListView.builder` 渲染 `AppListItem`。`AppListItem` 内部封装了 `MouseRegion` 与 `AnimatedContainer(duration: 100ms)`，背景色在 `Colors.transparent`、`bgCardHover` 与 `bgSelected` 之间切换。

## Goals / Non-Goals

**Goals:**
- 消除鼠标滑过时因 100ms 缓动延迟产生的多项同时变灰与快速拖影闪烁，实现 0 延迟即时反馈。
- 区分选中态（Selected）与悬停态（Hover）的视觉层级：选中态具备左侧 Accent 强调色指示条与高亮底纹，悬停态具备轻量、优雅且对比度明确的半透明浅色底纹。
- 修复浅色主题（Light Mode）下悬停背景（#F8FAFC）与面板底色（#F1F5F9）对比度严重不足、无法肉眼辨识的问题。
- 为 `ToolPanel` 的 `ListView.builder` 补齐 `ValueKey(tool.id)`，确保状态绑定稳定。

**Non-Goals:**
- 不改变折叠态（icon-only 52px）的既有行为，仅保证二者状态逻辑自洽。
- 不影响主工作区（右侧内容区）各工具的独立内部样式。

## Decisions

### 1. 悬停状态零延迟即时响应
- **决策**：将悬停态的背景色切换改为即时呈现（使用普通 `Container` 或将缓动时长降为 0ms，而非 100ms `AnimatedContainer`）。
- **理由**：在密集垂直列表中，移动光标的物理速度非常快（每秒可划过 5~10 个条目）。任何大于 30ms 的淡出延迟都会导致“上一项未淡出完毕，下一项已经淡入”，视觉上必然呈现“两项同时高亮并频闪”的瑕疵。原生 macOS 列表与 VS Code 侧边栏均采用即时 Hover 机制。

### 2. 区分选中态与悬停态（macOS 风格指示条）
- **决策**：
  - 选中态：背景采用 `bgSelected`（深色 #37373D / 浅色 #E2E8F0），左侧增加 3px 圆角 Accent 强调色垂直指示条（与左侧 `ActivityBar` 规范一致），标题文字与图标使用 `context.accentText`（或加粗强调）。
  - 悬停态：背景采用轻量半透明遮罩（浅色 `Colors.black.withValues(alpha: 0.045)`，深色 `Colors.white.withValues(alpha: 0.055)`，或通过主题 token 派生），前景文字与图标轻微提亮，无左侧指示条。
- **替代方案考虑**：仅微调灰色色值。缺点：在深色模式下，即使微调灰色，用户在余光中依然觉得是“两个灰色块”，视觉焦点模糊。增加指示条能从根本上消除层级歧义。

### 3. 浅色模式对比度保证
- **决策**：在浅色模式下，悬停背景不再采用接近纯白的静态常量 `#F8FAFC`，而是采用相对于面板底色明显可见的淡灰底色（`0xFFE2E8F0` 的微透明档或清晰的灰度阶），使肉眼悬停反馈清晰直观。

## Risks / Trade-offs

- **[Risk] `AppListItem` 在其他页面（如应用快捷方式）中被复用**  
  → **Mitigation**: `AppListItem` 的即时响应与对比度优化是纯视觉与交互体验升级，所有复用它的页面都将同时获益，无需破坏既有接口。
