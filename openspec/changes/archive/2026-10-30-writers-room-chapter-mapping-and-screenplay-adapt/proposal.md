## Why

在真实的影视短剧改编中，分集与原著小说章节绝非 1:1 的机械对应（如第 1 集通常浓缩提炼原著前 1~3 章的退婚或初遇高潮，中间某集可能是多章串联提炼）。目前剧本工作台默认死板按“集序号 = 章序号”展示和勾选原著章节，导致创作者面对数十上百回的小说章节无法判断当前集取材自何处。

因此，需要在“编剧研讨室”全季规划推演时由 AI 显式提取并标定每集对应的原著章节范围，定稿时持久化至剧集实体，并在剧本工作台与小说改编弹窗中智能关联预选，彻底打通“小说研讨 -> 章节对应 -> 精读改编”的闭环。

## What Changes

- **AI 约束引擎分集规划增强**：
  - 在全季宏观大幕规划与分集节拍推演任务中，要求大模型输出每集对应的原著章节范围（`chapter_range` 与 `chapter_indices`）。
  - 增强输出校验与平滑插值兜底逻辑，确保在非 1:1 映射下章节覆盖合理连贯。
- **数据模型与持久化**：
  - `StudioEpisode` 模型新增 `novelChapterRange` (String) 与 `novelChapterIndices` (List<int>) 字段，支持 JSON 序列化与向前向后兼容。
  - 研讨室在“定稿并同步至剧集库”时，将提取的章节映射信息同步写入对应剧集分集数据。
- **编剧研讨室界面可视度与人机共创**：
  - 在分集规划卡片上直观展示原著章节徽章（如 `[原著 1~3 章]`）。
  - 支持创作者直接点击/双击卡片手动微调章节范围（方案 A）。
  - 支持在右侧编剧对话协商中，通过自然语言指令要求 AI 调整特定集数的取材章节。
- **剧本工作台与改编弹窗智能联动**：
  - 剧本工作台未生成剧本时的推荐按钮与文案动态显示真实取材章节（如“精读原著第 1~3 章改编”）。
  - 点击打开 `ScreenplayNovelAdaptDialog` 时，自动预先勾选研讨室规划对应的多个章节，无需用户手动翻找。
  - 确认后直接将所选多章节全文无截断合并，送入现代长上下文大模型进行原汁原味影视化改编。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 增加编剧研讨室全季推演中的原著章节映射机制（chapter_range / chapter_indices），支持定稿持久化至分集实体，并在剧本工作台与小说改编弹窗中提供基于真实章节映射的智能预选、直观标记与人工微调支持。

## Impact

- **模型层**：`lib/tools/ai_video_studio/models/studio_models.dart` (`StudioEpisode`)。
- **服务层**：`lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（Prompt、SchemaValidator、章节平滑映射兜底）。
- **界面层**：
  - `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`（分集卡片徽章展示、手动微调输入、同步落库）。
  - `lib/tools/ai_video_studio/ui/screenplay_panel.dart`（动态章节按钮文案、向改编弹窗传递章节参数）。
  - `lib/tools/ai_video_studio/ui/screenplay_novel_adapt_dialog.dart`（多章节预选高亮、研讨室推荐章节提示）。
- **测试用例**：`test/ai_constraint_engine_test.dart`、`test/writers_room_materialization_and_dynamic_beats_test.dart`。
