# Proposal: 剧本工作台直通小说正文深度影视化改编工作流

## Why

目前在剧本工作台点击「AI 生成剧本」时，底层仅将当前集压缩后的约 100 字干瘪大纲（`synopsis`）送入大模型，导致 AI 缺失小说原著对话与细节、产生大量套路化脑补而严重偏离原著；而真正具备原文精读与受保护金句契约的「单章影视化改编」此前仅能通过创意孵化面板配置跳转，工作流割裂且违背用户直觉。在剧本工作台直接提供「从小说正文生成剧本」直通入口，让创作者就地挑选章节或粘贴正文一键生成原汁原味文学剧本，彻底解决原著还原度断流问题。

## What Changes

- **剧本工作台中央空白态（Empty State）新增「从小说正文改编剧本（推荐）」主入口**：与原有的「根据大纲扩写剧本」和「手动创建第一场」并列，醒目引导新集剧本制作。
- **剧本工作台顶部工具栏按钮重构与语义澄清**：将单一易误导的「AI 生成剧本」重命名并区分主次——主按钮为「从小说正文生成剧本」，下拉或次级按钮为「根据本集大纲扩写」，明确两者的信息源差异（数千字原文 vs 百字大纲）。
- **新增「从小说正文改编生成剧本」双通道弹窗（`ScreenplayNovelAdaptDialog`）**：
  - **通道 A（从本地小说库挑选）**：若剧集已绑定小说，自动列出该小说章节清单，支持多选 1~3 章（自动计算并提示总字数与最佳精读区间推荐）；
  - **通道 B（直接粘贴正文）**：提供多行文本框，支持用户任意粘贴 2,000~8,000 字外部小说章节或故事原文。
- **直通底层深度影视化与受保护契约沉淀管线**：用户确认后，直接调用 `AiConstraintEngine.adaptNovelDramaChapter` 提取戏剧场次、文学剧本正文与受保护金句/事实清单（`ProtectedContract`），通过 `StudioProjectManager.importChapterToEpisode` / `mergeMasterAssets` 增量合入主库并就地刷新当前剧本工作台。
- **Markdown 编辑器智能引导**：当用户在 Markdown 文本模式下粘贴大段非分场格式的小说散文时，提供快捷提示横幅「检测到小说正文，点击可一键 AI 改编为分场剧本」。

## Capabilities

### Modified Capabilities

- `ai-video-studio/script-workshop`: 剧本工作台新增基于小说正文（章节选择与纯文本粘贴）直接触发深度分场剧本生成的能力，明晰大纲扩写与正文改编双路径，并就地绑定受保护契约。
- `ai-video-studio/novel-import`: 扩展单集小说正文影视化改编的调用范围，使其不仅服务于创意孵化面板的全流程任务，亦可作为轻量级就地改编服务被剧本工作台直接驱动并沉淀资产。

## Impact

- **UI 层**：`lib/tools/ai_video_studio/ui/screenplay_panel.dart`（工具栏按钮结构、空白态入口、新增 `ScreenplayNovelAdaptDialog` 弹窗或拆分组件）。
- **服务层**：`lib/tools/ai_video_studio/services/studio_project_manager.dart` 与 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（复用现有 `adaptNovelDramaChapter` 与 `importChapterToEpisode`，无需修改破坏性存储结构）。
- **兼容性**：不改变现有剧集文件存储格式（`storyboard.json` / `screenplayText` / `protected_contract`），完全向后兼容。
