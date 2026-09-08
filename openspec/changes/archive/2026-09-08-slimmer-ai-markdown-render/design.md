## Context

`_showSingleAiDialog` 使用 `SelectableText` 渲染 AI 返回的 markdown 文本。AI 的 `diagnoseSingle()` prompt 要求"排版精美"，返回内容包含 `##` 标题、`**加粗**`、`-` 列表等 markdown 语法。`SelectableText` 不解析这些语法，导致原样显示。

## Goals / Non-Goals

**Goals:**
- AI 深度研判弹窗正确渲染 markdown 格式
- 样式与 AppTheme 保持一致

**Non-Goals:**
- 不改动其他页面的文本渲染（当前仅此处有 markdown AI 输出）
- 不引入复杂的 markdown 交互功能（如链接跳转、图片加载）

## Decisions

### 1. 使用 `flutter_markdown` 包

**选择**: 添加 `flutter_markdown` 依赖，使用 `MarkdownBody` 组件

**理由**: Flutter 官方推荐的 markdown 渲染方案，支持标准 markdown 语法（标题、加粗、列表、代码块、表格），`MarkdownBody` 支持文本选择，且可自定义样式。项目 Flutter SDK `^3.9.0` 完全兼容。

**替代方案**: 手写 `RichText` 解析器 — 拒绝，工作量大且只能覆盖部分语法，维护成本高。

### 2. 使用 `MarkdownBody` 而非 `Markdown`

**选择**: `MarkdownBody`（不带 `ScrollView`）

**理由**: 弹窗已有 `SingleChildScrollView` 包裹，`MarkdownBody` 直接嵌入即可，避免嵌套滚动冲突。

### 3. 样式映射

通过 `MarkdownStyleSheet` 将 markdown 元素映射到 AppTheme 风格：
- `h1/h2/h3` → `AppTheme.fontTitle` 风格，加粗
- `p` → `AppTheme.fontBody` 风格
- `code` → 等宽字体，背景色 `AppTheme.bgCard`
- `listBullet` → `AppTheme.accent` 颜色
- 整体颜色跟随 `AppTheme.textPrimary` / `AppTheme.textSecondary`

## Risks / Trade-offs

**[依赖引入]** 新增 `flutter_markdown` 包 → 该包为 Flutter 生态标准包，维护活跃，体积小（~100KB），风险可控。

**[AI 输出不稳定]** AI 可能偶尔返回格式异常的 markdown → `MarkdownBody` 对格式容错良好，不会崩溃。
