## Why

当前“AI 短视频工坊”在小说引入与解构处理中存在两大严重体验与链路断层：
1. **界面交互阻塞与层级割裂**：用户在小说选择弹窗中点击“确认引入并注入短视频工坊”后，主线程同步串行加载几十上百个章节的 SQLite 全文，界面死转圈卡死数秒至数十秒；更糟糕的是卡完之后紧接着又弹出二次模态确认弹窗，交互体验极差。
2. **处理过程黑盒与深层资产未驱动生成**：创建任务后仅有一个 18px 的小转圈，缺少类似流水线、时间轴的动态展示，用户无法得知正在执行什么动作或命令；同时，导演体系解构出的核心资产（角色形制、两段式镜头演变、音画分流策略）未能充分填充并驱动软件底层的图像与视频可靠生成。

## What Changes

- **选择器交互与导入执行解耦 (Non-blocking Ingestion)**：在 `NovelSelectorDialog` 内部集成“导入范围配置（单集扩写 vs 全季解构）”，点击确认后**立即秒关弹窗**，小说章节读取改为后台任务异步流式读取，彻底消灭界面死等与二次弹窗。
- **全生命周期流水线动态看板 (Pipeline Workflow Timeline)**：在创意孵化看板中重构导入进度卡片，提供：
  - 6 个核心里程碑阶段的时间轴（文本切片 ➔ 资产抽取 ➔ 场次节拍 ➔ 契约锁定 ➔ 五维拆镜 ➔ 门禁质检）；
  - 实时装配卡槽（角色卡、场景卡、道具卡、保护台词随解构实时动态冒出）；
  - 终端式实时动作日志流（Live Action Stream Console，呈现模型调用、当前处理章节、正在生成的动作指令）。
- **两段式时序演变与音画分流编译器 (Two-phase Prose & Audio Routing)**：
  - 升级提示词编译器，实现两段式镜头演变（前半段起始机位与主体动作 + 后半段特写/反转/末态）；
  - 确立清晰的音画分流规则：画面中严禁渲染对白文字与开口口型，原著对白明确标记为“画外配音 / 旁白”，状态明悟等信息标记为“系统浮字特效”，消灭视频画面乱码与嘴部畸变。
- **功能深度填充与原生批量出片链路 (Native Batch Generation Engine)**：
  - 将解构出的结构化数据无缝沉淀至 IP 主库（角色/场景/道具卡）和分镜看板；
  - 在分镜看板与交付面板提供原生的“一键批量生成首帧关键帧 ➔ 自动图生视频 ➔ 回传剪辑时间轴”全自动任务流水线，将脚本级能力转化为软件原生能力。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 支持选择器内联范围配置与后台流式读取，提供 6 阶段流水线动态时间轴、实时资产装配槽与实时动作日志流。
- `ai-video-studio/shot-continuity`: 支持两段式（前半段+后半段）时序摄影与动作演变编译，建立画外配音与系统浮字的音画分流规范。

## Impact

- 影响文件：`lib/tools/ai_video_studio/ui/novel_selector_dialog.dart`, `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`, `lib/tools/ai_video_studio/services/novel_import_task_service.dart`, `lib/tools/ai_video_studio/services/prompt_assembler.dart`, `lib/tools/ai_video_studio/ui/storyboard_board.dart`。
- 无破坏性变更（向后兼容既有剧集与分镜数据结构）。
