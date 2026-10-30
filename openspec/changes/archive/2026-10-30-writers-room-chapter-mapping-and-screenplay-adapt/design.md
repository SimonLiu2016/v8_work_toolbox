## Context

现有系统假定分集与原著小说章节为 1:1 映射（第 1 集对应第 1 章），但影视短剧实际通常为多章压缩或交叉剪辑提炼。目前编剧研讨室推演时未输出章节对应关系，`StudioEpisode` 实体未持久化章节字段，剧本工作台与小说改编弹窗直接依赖 `episode.index` 匹配，造成断层。

## Goals / Non-Goals

**Goals:**
- 在 `AiConstraintEngine` 全季分集推演与宏观大幕规划中引入原著章节映射字段（`chapter_range` 和 `chapter_indices`），并提供平滑插值兜底算法。
- 在 `StudioEpisode` 模型中持久化 `novelChapterRange` 与 `novelChapterIndices`，确保与历史工程完全向后兼容。
- 在编剧研讨室分集卡片上展示原著章节徽章，并提供点击手动微调章节弹窗（方案 A）。
- 在剧本工作台未生成剧本时，动态展示映射的原著章节并作为入口按钮文案。
- 在小说改编弹窗中根据传入的推荐章节自动预先多选勾选，并全量合并多章正文送入大模型生成剧本。

**Non-Goals:**
- 不对小说库原始文件进行物理切分或重排，仅在剧集维度建立元数据层面的引用与提取。
- 不引入复杂的段落摘要前置压缩器，对于多章正文保持原汁原味全量输入。

## Decisions

### 1. 数据模型与向后兼容 (StudioEpisode)
在 `StudioEpisode` 新增以下两个字段：
```dart
final String novelChapterRange;     // 格式如 "1-3"、"22-25" 或 "1, 3, 5"
final List<int> novelChapterIndices; // 解析后的章节序号列表，如 [1, 2, 3]
```
- 序列化 key 为 `novel_chapter_range` 和 `novel_chapter_indices`。
- 空缺时默认分别为 `''` 和 `const []`，旧剧集加载时平滑读取，不产生任何反序列化异常。

### 2. 章节范围字符串智能解析与兜底 (AiConstraintEngine)
实现 `_parseChapterRange(String rawRange, {int fallbackIndex = 1})`:
- 支持解析各种大模型常见输出格式：`"1-3"`, `"1~3"`, `"1, 2, 3"`, `"第1章~第3章"`, `"第1-3章"`。
- 若大模型未输出章节范围，结合全季 `adaptedChaptersRange`（如 1~60 章）与当前集序号，按进度比例进行平滑插值估算，避免出现空白或生硬的 1:1 回退。

### 3. 编剧研讨室交互与手动微调 (WritersRoomDialog)
- 在分集卡片（`_buildEpisodeCard`）集数和篇章标签旁，渲染 `[原著第 X~Y 章]` 标签。
- 点击该标签唤起微调弹窗，创作者可直接输入自定义章节范围（如将 `1-3` 改为 `1-2`），系统即时重新计算 `chapter_indices` 并刷新界面。
- 点击“定稿并同步至剧集库”时，将 `chapter_range` 与 `chapter_indices` 随同标题、大纲写入 `StudioEpisode` 存储。

### 4. 剧本工作台与小说改编弹窗无缝联动 (ScreenplayPanel & Dialog)
- `ScreenplayPanel` 检测到当前集具备 `novelChapterRange` 时，按钮显示 `精读原著第 X~Y 章改编`。
- 将 `episode.novelChapterIndices` 传递至 `ScreenplayNovelAdaptDialog`。
- 弹窗初始化时，如果包含传入的推荐章节，直接将其全部加入 `_selectedChapterIndices`，并呈现“💡 研讨室规划推荐章节：第 X~Y 章”高亮提示。
- 用户确认后，读取全部选中章节正文，以章节标题为分隔线拼接为完整长文本，全量送入 `AiConstraintEngine.adaptNovelDramaChapter`。

## Risks / Trade-offs

- **[多章节正文过长导致 Token 消耗增加]** → 现代大模型（Gemini 2.5 / Claude 3.5）拥有数十万字上下文容量，全量输入能够最大程度保全角色真实口吻与细微伏笔；若所选章节极端异常超过 8 万字，界面给出友好提示。
- **[大模型在分批规划时跨批次章节重叠或断层]** → 在阶段一大幕规划中显式为每个篇章分配 `chapter_range`，分批推演时将该篇章的章节范围作为强约束传入，并在归一化校验器中进行边界对齐。
