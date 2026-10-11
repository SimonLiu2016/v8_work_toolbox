## Context

当前短视频工坊（`lib/tools/ai_video_studio/`）已经具备三层项目管理（`StudioProjectManager`）、本地 JSON 文件持久化、AI 约束提示词引擎（`AiConstraintEngine`）以及分镜看板 UI。但其图像生成适配器在遇到中转站配置的 Agnes 视觉模型时缺乏专用参数组装，视频适配层硬编码了 SenseAudio 专属协议；同时创意孵化面板仅支持短文本概念输入，分镜看板缺少对短剧 3~5 秒、30~50 字具象微动作描写及全景景别的严格约束。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 在创意孵化面板提供小说文本文件（`.txt` / `.md`）导入，通过分层结构化提示词流水线自动解构全套 IP 主库（世界观、角色卡库、场景库、分集大纲与前情链）并持久化。
- 分镜看板支持景别“全景”（`full`），并升级 System Prompt 与解析校验器，确保单镜时长严格在 3~5 秒，画面描述控制在 30~50 字之间且遵循【主体 + 动作 + 环境】微动作具象化描写，台词标注预估秒数与情绪指令。
- 分镜看板提供“单集即时拆解”与“全剧一键批量流水线拆解”双模式。
- 在服务适配层完整实现 `AgnesImageAdapter` 行为增强与新增 `AgnesVideoAdapter`，通过用户已配置的 NewAPI 中转站（`http://119.29.249.154:3356`）平滑调用生成图像（2K, 9:16）与 720P 5秒视频片段。

**Non-Goals:**
- 不引入外部庞大的重量级 NLP 解析库，纯粹基于现有 `AiService.chat` 约束引擎进行多阶段智能提取。
- 小说导入与分镜拆解阶段不强制自动触发显卡生图生视频，仅生成结构化分镜与数据资产，保持为 `pending` 状态供创作者审阅把控。

## Decisions

### 1. 长篇小说到短剧 IP 的两阶段递进拆解（Two-Pass Arc Extraction）
- **架构决策**：
  - **Pass 1（全书宏观与资产解构）**：截取核心开局与主干章节摘要，抽取「世界观与风格 Tokens」、「主要角色卡库（含外貌金标准描写与中英文 Prompt）」、「常驻场景库」。
  - **Pass 2（剧情高潮检测与分集规划）**：以主线核心冲突为骨架，在剧情情绪峰值与重大反转处作为截断点（Hook），自动推荐划分为 N 集（如 10~15 集），生成每集的粗大纲（`synopsis`）、精炼前情（`summary`，<200字）与悬念钩子（`hook`）。
- **替代方案考虑**：
  - 一次性将整本几十万字小说连带所有分镜让 LLM 输出：由于上下文惩罚与单次输出 Token 上限，几乎 100% 会发生截断和幻觉，故坚决放弃。

### 2. 景别枚举与分镜数据模型升级
- **架构决策**：
  - 在 `StudioShotSize` 枚举中增加 `full('full', '全景')`，并在其 `fromId` 中兼容中英文标注（如 `全景`, `full`, `wide`）。
  - 更新 `StudioShot` 模型与 `ai_constraint_engine.dart` 中的 `_promptScriptBreakdown` 与 `_SchemaValidators.scriptBreakdown`：
    - `duration_sec`: 严格校验 `3.0 <= duration <= 5.0`。
    - `action_zh`: 校验字符数在 30 到 50 字之间，并在 Prompt 中强制【主体 + 动作 + 环境】微动作具象化规则。
    - `dialogue`: 注入预估秒数标注（例如 `（预估2.5秒）`）及情绪语气前缀。

### 3. 分镜看板双模式拆解机制
- **架构决策**：
  - **单集即时拆解**：针对当前活跃集调用 `AiConstraintEngine.scriptBreakdown`，以该集 synopsis 与上集 memory 为输入。
  - **全剧一键批量拆解**：在看板引入任务执行进度控制器，按集数顺序串行推进，每集拆解完成后自动将该集的实时精炼摘要更新至 `EpisodeMemory`，作为下一集的输入上下文，确保全剧人物逻辑与故事线高度连贯。

### 4. Agnes AI 视觉模型专用适配实现
- **架构决策**：
  - **图像生成 (`agnes-image-2.5-flash`)**：
    在 `SystemAiImageAdapter` 检测到模型为 `agnes-image-2.5-flash` 时，组织官方请求体：
    `size: "2K"`, `ratio: "9:16"`, `extra_body: { "response_format": "url", if (reference) "image": [ref] }`。
    成功后下载图片落盘，并保留线上公开 URL。
  - **视频生成 (`agnes-video-2.5-flash`)**：
    创建专门的 `AgnesVideoAdapter`（实现 `VideoGenAdapter` 与 `CancellableVideoGenAdapter`）：
    - 创建任务：调用中转站 `POST /v1/videos`，Payload 为 `{ "model": "agnes-video-2.5-flash", "prompt": ..., "mode": "keyframe", "size": "720P", "aspect_ratio": "9:16", "seconds": "5", "first_frame": "<URL/DataURI>" }`。
    - 轮询任务：优先请求 `GET /agnesapi?video_id=<ID>&model_name=agnes-video-2.5-flash`，若返回 404 则自适应回退到 OpenAI Videos 标准的 `GET /v1/videos/<ID>`，直至 `status: "completed"` 获取成片 `url` 并下载落盘。
    - 在 `VideoGenAdapterFactory` 中优先路由中转站全局配置的 Agnes 模型。

## Risks / Trade-offs

- **[Risk] 超长小说读取耗时过长导致 UI 冻结**
  → Mitigation: 文件读取与分段分析全部放入后台异步执行，前端展示带有步骤反馈的 Loading 对话框（如：正在分析全书世界观 -> 正在提炼主要角色 -> 正在规划剧情分集）。
- **[Risk] 中转站轮询超时或网络波动**
  → Mitigation: 设定 5 分钟超时与指数退避重试，支持用户在任务队列中随时取消单任务（`CancellableVideoGenAdapter`）。
- **[Risk] 分镜字数或时长未能一次性严格命中 30~50 字**
  → Mitigation: `AiConstraintEngine` 内置最多 3 次失败自动 retry，并在 System Prompt 中给出格式示范；若 3 次耗尽，自动进行合规修正与兜底。

## Migration Plan

本变更为纯增量和适配器重构，不破坏任何旧版剧集的 JSON 存储结构。已有的历史剧集仍然可正常打开与播放，新增字段具备默认值兼容。
