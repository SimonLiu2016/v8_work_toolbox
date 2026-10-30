## Context

当前漫剧工作台在生成视频时，全量分镜均使用默认 `auto` 并因首帧存在而被强制升格为 `keyframe` 模式，无法使用 Agnes 的 `reference`（多图参考）与 `text`（纯文本）模式；同时生成的提示词堆叠了矛盾的光照、场景、运镜与无效的 180° 轴线标记；AI 拆镜存在动作过载与景别单一；多人同框时内心独白被误分配给其他角色口型；并且画幅比例硬编码为 9:16，AI 系统提示词写死在代码中无法配置。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 在 `StudioShot` 中引入 `videoMode`，实现 `auto` 智能路由与分镜看板用户手动切换，严格按照 Agnes 规范分流素材入参（keyframe / reference / text 互斥）；
- 建立“剧集主档案默认设置 + 分镜按需覆盖”的画幅比例（9:16 / 16:9 / 21:9 / 4:3 / 1:1）与分辨率（1K/2K/4K/720P/1080P）流转体系；
- 实现 `StudioAiTask.videoPromptRewrite` 提示词消解重写 AI 任务与 `PromptAssembler` 规则级排他兜底；
- 在 5D 导演拆镜提示词中严厉注入五大视听铁律约束（单镜单一动作、主体聚焦、运镜排他、微表情递进、景别交替）；
- 扩展导演质检 C10 规则并在质检报告中提供一键 AI 自动修复工具箱；
- 视频提示词内心独白彻底去除机器标记，采用全员显式闭口正向守卫；
- 将全流程 8 套核心 AI 系统提示词全部收拢至 `StudioPresetStore`，在“预设与提示词管理”UI 中开放自由配置。

**Non-Goals:**
- 不改变底层 HTTP 网络重试与任务轮询协议；
- 不破坏现有工程的单集与分镜数据持久化文件格式（所有新增字段均提供安全默认值向后兼容）。

## Decisions

### 1. 视频模式多路复用与参数分流（`videoMode`）
- **决策**：`StudioShot` 增加 `videoMode` 字段（取值：`auto`、`keyframe`、`reference`、`text`）。
  - `auto` 智能判定：若无角色且无场景参考图，或动作为超大爆发位移，推荐 `text`；若存在角色/场景图但未锁定关键帧，推荐 `reference`；若关键帧已生成且为主体近景/对白，推荐 `keyframe`。
  - 在 `studio_generation_tasks.dart` 的 `generateShotVideoTask` 中分流参数：
    - `keyframe`：传 `inputImage` 与 `lastFrameImage`，`referenceImages` 置空；
    - `reference`：`inputImage` 置 null，传 `referenceImages`（出场角色 3 视图 + 场景图）；
    - `text`：图片入参全部置 null/空。
- **替代方案考虑**：仅在云端由适配器自行猜测模式。弊端：无法满足专业创作者对特定镜头需要完全自由动态（text）或需要多角色参考（reference）的明确意图。

### 2. 画幅比例与分辨率的“主库默认 + 分镜覆盖”架构
- **决策**：
  - `StudioSeries` 新增 `defaultAspectRatio`（默认 `'9:16'` 或 `'16:9'`）与 `defaultResolution`（图像默认 `'2K'`，视频默认 `'720P'`）；
  - `StudioShot` 新增可选覆盖字段 `aspectRatio` 与 `resolution`；
  - 任务层通过 `StudioImageDimensionPreset.fromRatio` 动态换算宽高像素并向生成接口直通注入 `ratio` 与 `sizeTier`。
- **替代方案考虑**：仅在分镜层配置。弊端：用户每部剧有几十个分镜，若要做一部 16:9 的短剧，逐镜修改比例体验极差，必须由剧集主库提供默认值。

### 3. 双层提示词冲突消解与电影化重写引擎
- **决策**：
  - **第一层（确定性规则兜底）**：在 `PromptAssembler.buildVideoGenPrompt` 中自动丢弃单镜无效的 180° 轴线标记，若检测到推拉摇移运镜则自动清除“定机位”冲突词；
  - **第二层（AI 智能重写任务）**：实现 `StudioAiTask.videoPromptRewrite`，将地标冲突、光影对冲、反向情绪词消解为 80~140 字的纯净中文视频大模型执行稿。

### 4. 全员显式闭口画外心声正向守卫
- **决策**：只要镜头为内心独白，彻底移除 `[角色内心独白/心声]`，在视频提示词中显式点名场景中出场的所有角色姓名，构造强正向约束：`画面中包括 [A、B] 等在场全员嘴唇全程严密闭合，不张嘴，无口型，全员保持沉思/冷峻神态`。

### 5. 提示词可配置化体系与质检 AI 一键自愈
- **决策**：
  - 在 `StudioPromptTemplate` 增加 8 套全流程任务模板，`AiConstraintEngine.systemPromptFor` 统一走 `StudioPresetStore.instance.getPromptContent`；
  - 质检报告增加 `AiConstraintEngine.autoFixAuditIssues`，将 C01~C10 违规信息交由 AI 自动调配合规分镜。

## Risks / Trade-offs

- **[Risk] 旧版 series_profile.json 或 storyboard.json 缺少新增字段导致解析异常** → **[Mitigation]** `fromJson` 全部提供优雅兜底默认值（`defaultAspectRatio` 兜底 `'9:16'`，`defaultResolution` 兜底 `'2K'` / `'720P'`，`videoMode` 兜底 `'auto'`）。
- **[Risk] 用户自定义了错误的 System Prompt 导致 AI 无法输出合规 JSON** → **[Mitigation]** 在 `AiConstraintEngine.run` 中保持 `parseJsonLoose` 失败自动 retry 机制，并在 UI 中提供一键“恢复出厂默认提示词”按钮。
