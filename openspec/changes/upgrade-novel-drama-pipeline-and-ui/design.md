## Context

当前短视频工坊在小说导入与分镜生产中，已具备 `drama_director_contract.dart` 数据模型以及 C01~C09 质检引擎。但在实际使用中：
1. `NovelSelectorDialog` 在点击确认时，以未带进度的模态遮罩同步遍历 SQLite 读取全部章节文本，随后在主页面又弹出 `_showImportScopeDialog`，操作体验卡顿且割裂；
2. `NovelImportTask` 仅暴露 `ImportPhase`（三个大阶段），UI 层 `_ImportProgressCard` 仅显示单行旋转指示器，缺乏阶段时间轴、实时资产冒出和控制台输出；
3. `PhotorealisticPromptCompiler` 生成的提示词较为单一，未利用“前半段+后半段”的时序运镜与动作转换，且缺少音画分流标记，导致视频画面经常尝试生成台词或文字。

## Goals / Non-Goals

**Goals:**
- 将范围选择内嵌至 `NovelSelectorDialog`，点击“确认引用”后即刻关闭弹窗（0ms 等待感），文本异步加载交由 `NovelImportTaskService` 后台处理。
- 在 `NovelImportTask` 中增加细粒度步骤推进事件流（`StepEvent`）与实时装配状态（提取到的角色、场景、道具、场次数量），供 UI 订阅。
- 在 `idea_incubator_panel.dart` 落地包含“6 阶段节点时间轴 + 动态装配卡槽 + 实时动作日志流”的流水线看板组件。
- 升级 `PhotorealisticPromptCompiler` 与 `CameraStagingCompiler`，支持两段式时序演变（Start phase + Climax/Detail phase）与音画分流规则。
- 在看板和交付端打通“批量出帧 ➔ 自动图生视频 ➔ 剪辑时间轴对齐”的原生闭环。

**Non-Goals:**
- 不重构本地数据库底层架构（仍使用既有 SQLite 与 Drift / `NovelRepository`）。
- 不破坏既有分镜与剧集的 JSON 存储模式，保持向后兼容。

## Decisions

### 1. 弹窗内联范围与延迟加载 (Inline Scope & Lazy Chapter Fetching)
- **决策**：在 `NovelSelectorDialog` 右侧直接放置「导入范围：全季解构 / 单集扩写」单选组件和集号选择器。点击确认时，只返回选中的 `novel.id`、`novel.title` 和 `selectedChapterIndices`，**不立刻遍历数据库读取全文**。
- **替代方案与权衡**：在弹窗内读取全文会导致整书（如 200 章）加载数秒卡死 UI 线程；延迟到后台 Task 异步按需流式拉取，UI 响应可在 16ms 内完成。

### 2. 流水线阶段与事件流设计 (Pipeline Events & Live State)
- **决策**：在 `NovelImportTask` 中新增：
  - `List<PipelineStage> stages`：6 个核心阶段（`ingest`, `assets`, `beats`, `contract`, `storyboard`, `audit`）；
  - `List<String> liveLogs`：滚动日志流（最多保留 200 条）；
  - `List<String> discoveredCharacters`, `discoveredScenes`, `discoveredProps`；
  - `int protectedUtteranceCount`。
- **替代方案与权衡**：使用 WebSocket 或复杂 isolate 端口通信成本过高。因 `NovelImportTaskService` 为 Flutter 进程级 `ChangeNotifier` 单例，直接通过内存对象状态更新并在关键节点 `notifyListeners()`，开销极小且完美契合 UI 订阅。

### 3. 两段式镜头演变与音画分流编译 (Two-phase Prose & Audio Routing)
- **决策**：
  - 将每个分镜的自然语言编译拆为：
    - `Phase 1 (前半段)`：机位移动（如跟拍、推近）、环境与初始动势；
    - `Phase 2 (后半段)`：动作爆发、特写焦点切换（如刀插烤鸡、面纱微红）、受击位移与定格末态。
  - 严格剔除画面内的文字生成描述，台词一律输出为 `[画外配音: <台词>]`，修为/属性突破一律输出为 `[边缘半透明金色系统浮字特效]`。
- **替代方案与权衡**：单段式简单拼接虽然词数少，但视频生成模型极易生成静态无变化画面；两段式演变能够有效触发目前主流视频模型（如可灵、即梦、Agnes）在单段 5~10 秒内的戏剧性运镜变化。

## Risks / Trade-offs

- **[Risk] 大章节合并后 Prompt 超出 LLM 上下文** → **Mitigation**: 后台流式拉取时对单次分析语料做动态截断或按节切片（Chunking），单批次不超过 30,000 字。
- **[Risk] 流水线日志频繁 notifyListeners 导致 UI 掉帧** → **Mitigation**: 对日志刷新使用节流（Throttle 200ms），避免高频连续渲染。
