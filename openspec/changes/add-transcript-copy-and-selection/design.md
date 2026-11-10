## Context

精听文稿抽屉（`TranscriptDrawer`）通过 `ListView.builder` 渲染会议/排练话轮列表。当前每行正文使用不可选取的 `RichText`，且整行被 `InkWell` 点击捕获用于跳转音频。本设计改造正文渲染及手势分层，实现鼠标划词与一键复制。

## Goals / Non-Goals

**Goals:**
- 在“标准原文”、“意群断句”以及翻开后的“盲听遮罩”中，文本全面支持鼠标拖选、双击选词、右键复制。
- 在每个话轮操作栏新增 `📋` 按钮，标准模式下一键拷贝纯英文，意群断句下一键拷贝格式化带 `//` 的排版文本。
- 文本操作与音频播放跳转（Seek）彻底解耦，选词拖拽绝不触发重新播放。

**Non-Goals:**
- 不支持跨发言轮次的鼠标整体连续划选（跨轮次划选会包含说话人及操作按钮，破坏复制格式；用户若需多轮次可通过一键复制多项或在词汇表中导出）。
- 不引入外部第三方富文本选择依赖，全部基于 Flutter 原生机制与现有高亮器。

## Decisions

### 1. 使用行内 `SelectableText.rich` 代替全局 `SelectionArea`
- **选型考虑**：全局 `SelectionArea` 在包含 `IconButton`、`TextButton`、发言人署名等多层复杂条目的列表内拖拽时，极易选中图标字体、无序错位；而各行内部采用 `SelectableText.rich` 能够精确界定文本边界，并天然与现有 `TermHighlighter.highlight` 及 `ConnectedSpeechMarker.buildSpans` 返回的 `TextSpan` 完美契合。
- **备选方案**：全局 `SelectionContainer`，但因存在跨组件边界选中操作按钮的体验缺陷而被否决。

### 2. 隔离播放跳转手势区域
- **手势分层**：
  - 左侧说话人栏（`SizedBox(width: 88)`）包裹 `InkWell`，鼠标悬浮时展示手型及“点击跳至该句播放”提示；
  - 中间正文区域（`Expanded`）独立放置 `SelectableText.rich`，不套外层点击跳转，完全由文本光标手势接管；
  - 既保留了快速跳播的便利性，又杜绝了划词选词时的误触发。

### 3. 一键复制的排版格式策略
- **标准原文模式**：拷贝 `turn.rawText.trim()`，去除所有标号与说话人署名，保证粘贴到 AI 对话框（如 ChatGPT/Claude）时最纯净。
- **意群断句模式**：通过 `SenseGroupChunker.chunk(turn.rawText)` 生成多行格式，格式为：
  ```text
  1. <意群文本> //
  2. <意群文本> //
  3. <意群文本>
  ```
  外部大模型接收此格式后可直接审阅呼吸停顿点与语义主干划分。

## Risks / Trade-offs

- **[选择文本与行高微调]**：`SelectableText.rich` 在极少数缩放比例下光标选取可能引起内边距细微重排。
  → 对策：显式指定固定的 `fontSize` 与 `height`（行高乘数），保证与原本 `RichText` 视觉一致。
