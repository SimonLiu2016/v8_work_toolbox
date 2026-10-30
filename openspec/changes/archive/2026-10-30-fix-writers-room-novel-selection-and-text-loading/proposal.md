## Why

创作者在“编剧研讨室”（`WritersRoomDialog`）点击“选择小说全本/章节”或“立即从小说库选择”，在小说选择弹窗中选中小说并点击“确认引用并注入短视频工坊”后，选择窗口关闭，但研讨室没有任何反应，界面依旧停留在初始空白欢迎引导页，给用户造成“功能失灵卡死”的错觉。

经代码全链路追踪，根本原因为：
1. `NovelSelectorDialog` 退出时将 `NovelSelectionResult.combinedText` 硬编码为 `''`（设计初衷是让异步解构服务在后台按任务慢慢读，但未考虑前台即时工作台的消费诉求）；
2. `WritersRoomDialog` 仅判断 `if (_novelText.isNotEmpty)`，当接收到空字符串时静默忽略，既未向本地小说库 `NovelRepository` 补读章节正文，也未给用户任何提示；
3. `AiConstraintEngine.extractWritersRoomMaster` 未接入长文本智能窗口采样保护，当传入几十万字甚至数百万字小说全本时存在 LLM 上下文溢出崩溃隐患。

修复此问题能打通全季编剧研讨室与本地小说库之间的核心业务闭环，让创作者顺畅实现小说全本一键导入并开启全季分集大纲共创。

## What Changes

- **`NovelSelectionResult` 封装统一的正文自愈加载方法**：
  - 新增 `loadCombinedText()` 方法：若已有 `combinedText` 则直接返回；若为空且指定了 `novel.id`，自动调用 `NovelRepository` 批量查询读取所选章节（全本时自动提取所有章节索引）正文并格式化拼接。
- **“编剧研讨室”打通正文载入全流程与状态反馈**：
  - 在小说选择弹窗关闭后，立即展示加载状态（`“正在从本地小说库载入《XXX》章节正文...”`）；
  - 调用 `loadCombinedText()` 异步取得正文；
  - 若章节内容均为空（如仅建索引未抓取内容），给出明确的 SnackBar 提示（`“所选小说暂无章节正文，请先在小说管理器中下载或导入正文”`）并复位状态；
  - 若内容有效，自动启动 AI 编剧总监宏观主线与必留/可删情节分析，并顺利推进至全季分集策划。
- **大模型长文采样保护**：
  - 在 `AiConstraintEngine.extractWritersRoomMaster` 中引入 `sampleNovelTextForContext`，在保留小说开头铺垫、结尾决战高潮与中段重要转折的同时限制总字符预算在 35,000 字以内，杜绝大模型 Context Window 溢出。

## Capabilities

### New Capabilities

<!-- 无全新能力域 -->

### Modified Capabilities

- `ai-video-studio/novel-import`: 补充编剧研讨室从小说库引用资产的正文自愈加载规约、章节正文为空时的防御引导规约以及长文主线分析阶段的上下文智能采样保护规约。

## Impact

- **UI 层**：
  - `lib/tools/ai_video_studio/ui/novel_selector_dialog.dart`: 在 `NovelSelectionResult` 中扩展 `loadCombinedText()`。
  - `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`: 在 `_pickFromNovelLibrary` 中实现加载态、正文补读自愈、空内容防御与自动启动分析。
- **服务层**：
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 在 `extractWritersRoomMaster` 方法中加入 `sampleNovelTextForContext` 采样保护。
- **测试**：
  - 编写 `test/writers_room_novel_selection_test.dart` 自动化测试，验证章节正文批量加载、空内容边界处理以及采样机制。
