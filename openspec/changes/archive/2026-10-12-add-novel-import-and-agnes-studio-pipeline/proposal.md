## Why

用户中转站已成功接入并配置 Agnes AI 最新的视觉模型（`agnes-image-2.5-flash` 与 `agnes-video-2.5-flash`），但当前“短视频工坊”中的图像与视频适配层存在协议与参数断层：图像适配器缺乏 Agnes 原生所要求的档位控制（2K/9:16）与参考图结构，而视频适配层则完全缺失通用中转站调用及 Agnes 专属接口（`/v1/videos` 与任务轮询），导致工坊无法通过中转站生成视频。

同时，短剧制作前端流程存在关键断层：在“创意孵化”中缺少从完整小说文本文件直接导入并自动提取拆解全套 IP 主库（角色卡、场景库、世界观、集数与前情钩子）的能力；在“分镜看板”中缺乏对短剧工业级标准（单镜 3~5 秒、远景/全景/中景/近景/特写五景别、30~50 字具象画面描述、含预估秒数与情绪语气的台词）以及逐集/批量逐步拆解分镜的完整支持。

## What Changes

- **中转站 Agnes 视觉模型专项支持**：
  - 增强 `SystemAiImageAdapter`，当模型为 `agnes-image-2.5-flash` 时自适应切换为 Agnes 原生图像协议（`size: "2K"`, `ratio: "9:16"`, `extra_body.response_format: "url"`, `extra_body.image: [reference]`）。
  - 新增 `AgnesVideoAdapter` 并重构 `VideoGenAdapterFactory` 与通用视频槽位解析，遵循官方 OpenAI Videos 兼容标准调用中转站 `POST /v1/videos`（`model: "agnes-video-2.5-flash"`, `mode: "keyframe"`, `size: "720P"`, `aspect_ratio: "9:16"`, `seconds: "5"`），并支持轮询 `/agnesapi` / `/v1/videos/{id}` 自动下载成片 MP4。
- **小说直接导入与全案自动拆解流水线**：
  - “创意孵化”面板增加导入文本文件（`.txt` / `.md`）入口。
  - 引入基于剧情高潮检测与网文短剧节奏转换的长文理解引擎，自动完成：
    - **世界观设定**：时代、核心设定、冲突法则、全局视觉风格 Tokens。
    - **角色卡库**：主配角外貌描写金标准、性格与中英文正负向 Prompt。
    - **场景库**：核心发生地描述与英文 Prompt。
    - **分集大纲与前情链**：根据剧情高潮自动推荐划分集数（每集包含标题、剧情大纲 synopsis、前情记忆 summary、集尾悬念钩子 hook）。
  - 拆解成果原子化保存至本地 IP 主库（`series_profile.json`、`characters/`、`common_scenes/`、`episodes/`）。
- **分镜看板：剧本与分镜逐步拆解**：
  - 景别枚举扩展：在 `StudioShotSize` 中正式补充“全景”（`full`），统一支持“远景 / 全景 / 中景 / 近景 / 特写”。
  - 四字段硬约束升级：
    1. 镜号（连续递增）；
    2. 景别（五景别选择）；
    3. 画面描述（严格控制在 30 ~ 50 字之间，强制【主体 + 动作 + 环境】微动作具象化描写）；
    4. 台词/旁白（明确标注预估秒数及配音语气情绪指令）。
  - 时长硬约束：单镜建议时长严格限制在 3 ～ 5 秒之间。
  - 双模式拆解：分镜看板支持“单集即时拆解”与“全剧一键批量流水线拆解”双模式，分镜生成后图片与视频默认占位待审阅。

## Capabilities

### New Capabilities
- `ai-video-studio`: 提供短视频工坊完整能力，包括小说文件直接导入与 IP 主库全案拆解、剧情高潮驱动的集数划分与前情链生成、分镜看板双模式剧本分镜拆解（四字段与 3~5 秒约束）、以及中转站 Agnes Image 与 Agnes Video 模型的端到端调用生成。

### Modified Capabilities
<!-- 无现有 capability 发生需求变更 -->

## Impact
- **代码影响**：
  - `lib/tools/ai_video_studio/models/studio_models.dart`（增加 `StudioShotSize.full` 全景枚举）
  - `lib/tools/ai_video_studio/services/image_gen_adapter.dart`（增强 Agnes Image 协议参数适配）
  - `lib/tools/ai_video_studio/services/video_gen_adapter.dart`（新增 Agnes Video 适配器与工厂路由）
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（新增长篇小说剧情拆解任务、优化分镜拆解 System Prompt 与 Schema 校验）
  - `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`（增加小说文件导入与自动入库 UI 交互）
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`（增加全景支持、批量/单集拆解进度控制及新字段约束呈现）
- **依赖与系统**：利用现有的中转站 HTTP 通信与 Keychain 凭据管理，无需新增第三方依赖。
