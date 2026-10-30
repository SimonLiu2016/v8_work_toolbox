## Context

当前剧本工作台内存在 `List<DramaScene> _scenes`（结构化场次节拍）与 `String _screenplayText`（全文文学剧本）两种形态，并且已经支持 `DramaScene.exportToMarkdown(scenes)`。分镜看板中维护当前分集的镜头列表 `episode.shots`，每个镜头携带 `number`、`targetDuration`、`visual`（提示词与描述）、`dialogue`、`dialogueSpeaker`、`cameraMovement`、`scale`、`props` 等关键视听属性。

在此之前缺少剧本文件的直接导入和导出功能，且分镜看板缺少对全集镜头的结构化表格导出。

## Goals / Non-Goals

**Goals:**
- 在剧本工作台实现外部文本（`.md`, `.txt`, `.fountain`）的导入，能智能识别并分拆标准分场（识别 `# 第X场` 等标识），无分场时无缝置入文本编辑器。
- 在剧本工作台提供整集剧本导出为 `.md` 和 `.txt` 本地文件。
- 在分镜看板顶部提供整集分镜表导出为标准 Markdown 表格 (`.md`) 与带 UTF-8 BOM 的 CSV 工业分镜表格 (`.csv`)。
- 在全流程中提供防误触覆盖确认与保存完成后的访达定位快捷操作。

**Non-Goals:**
- 不引入外部庞大的重量级解析库，利用轻量高效的正则与状态机处理剧本分场。
- 不修改底层已有的 `DramaScene` 与 `StudioShot` 数据模型存储结构，保证与既有工程百分之百向后兼容。
- 不替换分镜看板已有的“单个镜头素材导出”与“剪映工程草稿导出”，本变更聚焦于“人类可读的分镜表协同文件”。

## Decisions

### 1. 外部剧本导入探测策略（方案 A）
- **决定**：导入剧本文件后，先进行轻量场次标记探测（正则匹配 `r'(?m)^ *(?:#+ *)?(?:第\s*[0-9一二三四五六七八九十百]+\s*场|SCENE\s+\d+|INT\.|EXT\.|内景|外景)'`）。
- **理由**：编剧常见的排版有多种规范。如果命中分场标记，则自动按场拆分为 `DramaScene`；若完全是一篇无标记的散文或连续旁白文本，则直接保持原文存入 `_screenplayText` 并切至 `_isRawTextMode = true`，让用户在富文本编辑器中自由编辑，体验平滑，无需用户在导入时做复杂的多选配置。
- **备选方案**：每次导入都强制弹窗询问。否定原因：增加了绝大部分使用规范剧本文件的用户的点击步骤。

### 2. 分镜表导出文件格式与内容组织
- **决定**：
  - **Markdown 分镜表 (`.md`)**：顶部输出分集元数据（项目名、第X集、集名、镜头数、预估总时长），下方使用 GitHub Flavored Markdown (GFM) 表格按镜头逐行排列关键字段（镜号、景别、运镜、画面提示、台词与说话人、时长）。
  - **CSV 分镜表 (`.csv`)**：首字节添加 UTF-8 BOM (`\uFEFF`)，使用标准 RFC 4180 转义规则（用双引号包裹含逗号、换行和双引号的单元格）。
- **理由**：UTF-8 BOM 是 Windows 与 macOS 上的 Microsoft Excel / WPS 正确识别中文字符集所必需的；CSV 格式可直接无缝导入飞书多维表格、Notion 或钉钉；Markdown 格式适合在 Obsidian、Typora 中快速查看或打印。

### 3. 文件读写与系统交互
- **决定**：统一使用项目现有的 `FilePicker.platform.pickFiles` 和 `FilePicker.platform.saveFile`，并结合 `Process.run('open', ['-R', filePath])` 在 macOS 上提供「在访达中显示」的交互。
- **理由**：保持与项目其他模块（如素材导出、三视图导入）一致的原生 macOS 桌面端体验。

## Risks / Trade-offs

- **[Risk]** 某些剧本的场次格式极为小众导致未能识别出分场。
  - **Mitigation**：即便未能识别，文本也会完整保留在 Markdown 全文模式中，不会造成用户数据丢失。随后用户可以点击顶部的「切换模式」或「从小说/大纲重拆」进一步处理。
- **[Risk]** 分镜台词或提示词中包含换行符导致 CSV 排版错乱。
  - **Mitigation**：严格使用带引号转义的 RFC 4180 CSV 编码函数，确保换行符与双引号均被正确包裹转义。
- **[Risk]** 导入覆盖当前未保存的剧本草稿。
  - **Mitigation**：在 `_scenes.isNotEmpty` 或 `_screenplayText.isNotEmpty` 时，弹出警告对话框让用户显式确认才执行覆写。

## Migration Plan

- 无数据库迁移要求，纯 UI 与本地 I/O 能力扩展。
- 遵循工程规范，代码实现完成后运行 `./scripts/deploy_local.sh` 重新构建并热替换本机应用。
