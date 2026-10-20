## Context

当前工程在 `lib/tools/ai_video_studio/` 中已具备任务队列、持久化台账（Ledger）、角色/场景资产卡、生图/生视频适配器以及剪映导出等底层基建。但上游的小说解析和分镜拆解链路严重断层：小说长文本被一次性暴力压缩为 300 字大纲，分镜拆解直接由大纲跳跃至包含简单微动作的单镜列表，缺乏场次（Scene）/节拍（Beat）规划、五维导演决策（物理动势、空间光影、光学调度、时间演变、美学质感）、攻防因果链以及动态连续性支持。

本设计基于 `/Users/simon/Desktop/临时文件/modular-drama-director` 的工业级体系，在纯 Dart/Flutter 架构下实现全链路重构。

## Goals / Non-Goals

**Goals:**
- 实现端到端闭环的小说影视化工业管线：小说原著 → 剧本场次与保护清单 → 五维导演决策分镜 → 空间站位与攻防编舞 → 平台级提示词编译与 C01~C09 质检。
- 在 Dart 端原生实现 `modular-drama-director` 核心逻辑，零外部 Python 进程依赖，保证 macOS 沙盒与离线可用性。
- 数据模型全面向后兼容：现有 `StudioEpisode`、`StudioShot`、`ShotContinuity` 增加新字段并提供默认值，不破坏已有剧集工程的加载与落盘。
- 解决动作戏“回合制假把式”与空间错位：引入 Combat DNA、六步攻防链（意图→动作→交互→受力→位移→接力）、3~4 镜连续攻击组以及 180° 摄影轴线。
- 升级 `PromptAssembler`，支持即梦 Seedance（任务化执行稿 + 剪辑接力边 Handoff）、商用视频 API（可灵 / Runway / CogVideo 自然语言摄影四段式）以及 H3 CSV。

**Non-Goals:**
- 不重构现有的底层图像/视频生成适配器（`ImageGenAdapter`、`VideoGenAdapter`）的 HTTP 请求逻辑。
- 不引入外部本地 Python 运行时守护进程（所有校验与渲染在 Dart 侧原生执行）。

## Decisions

### D1: 纯 Dart 原生移植 vs 外部 Python 进程调度
- **选择**：在 Flutter/Dart 内部原生实现 `DramaDirectorContract`、`DirectorValidationEngine` 与 `PlatformPromptCompiler`，完全摆脱对外部 Python 脚本环境的依赖。
- **理由**：macOS App 包含沙盒与权限隔离要求，调用外部 Python 容易遭遇解释器缺失、pip 依赖冲突或安全权限阻断；Dart 原生实现执行速度快、跨平台稳定、且能直接与 Flutter 响应式状态（ChangeNotifier）绑定。
- **备选方案**：通过 `Process.run('python3', ...)` 运行 Skill 自带脚本。被否决，因环境依赖脆断、部署复杂。

### D2: 分层数据模型演进（兼容旧版 JSON）
- **选择**：在 `lib/tools/ai_video_studio/models/` 中新增 `drama_director_contract.dart`，并对 `studio_models.dart` 进行平滑扩展：
  - `DramaScene` / `DramaBeat`：代表场次与节拍层级，隶属于 `StudioEpisode`；
  - `ProtectedContract`：挂载于 `StudioEpisode`，存储锁定事实（`facts`）与基准对白清单（`utterances`）；
  - `DirectorDecisions`：挂载于 `StudioShot`，存储五维导演决策参数（物理动势、光影、光学四段式机位、时间负荷、美学质感）；
  - `CombatStep` / `CombatGroup`：挂载于动作镜头，存储攻防六步链与接力数据；
  - `DynamicExitState`：挂载于 `ShotContinuity`，追踪支撑脚平衡、速度矢量与未完成动作相位。
- **兼容策略**：所有新增字段在 `fromJson` 时均为可空或提供静态默认值，旧剧集加载时直接平滑升级。

### D3: 模块化 System Prompt 注入架构
- **选择**：升级 `AiConstraintEngine`，按题材与阶段实现模块化路由加载：
  - `novelChapterDramaAdaptation`：通读长文单章，输出四阶段影视大纲 + 场次规划 + 保护清单；
  - `scriptBreakdown5D`：文戏与常规场景加载五维导演决策系统 Prompt；
  - `actionCombatBreakdown`：打斗、追逐、玄幻动作场景联合加载动作专项编舞 Prompt（Combat DNA + 3~4 招连续攻击组）；
  - 按需载入光影（`lighting`）与空间站位（`spatial-blocking`）约束，避免单次 LLM 请求 Prompt 超长引发截断。

### D4: 自动化可执行性审计关口（C01~C09）
- **选择**：在分镜生成完毕和视频提交前，由 `DirectorValidationEngine` 进行纯本地毫秒级规则静态校验：
  - 检查时长与台词字数比例（> 6 字/秒报警告）；
  - 检查相邻镜头是否存在 180° 轴线翻转与空间地标突变；
  - 检查打斗镜头是否具备受力和位移反馈；
  - 检查引用角色与场景是否在 IP 资产库内；
  - 校验结果分为 `PASS`、`WARNING`（提示可继续）、`BLOCKING`（强拦截并高亮错误分镜卡片）。

## Risks / Trade-offs

- **[Risk 1: 复杂提示词导致小型/免费 LLM 格式解析率下降]**
  → **Mitigation**: 沿用工坊现有的 `parseJsonLoose` 宽容解析机制，并在 `AiConstraintEngine` 中实行带上一次原始报错回显的最多 3 次自动纠错 Retry；对五维决策与攻防链提供扁平化清晰 Schema。
- **[Risk 2: 长篇小说篇幅过长可能超出单次上下文上限]**
  → **Mitigation**: 保留章节选择器（`NovelSelectorDialog`），以单章（3000~8000字）作为影视化深度提炼的最佳处理单元；全季规划仅处理目录与粗事件。
- **[Risk 3: UI 界面复杂度上升]**
  → **Mitigation**: 分镜看板采用“主副视图”折叠设计——默认展示精炼的画面描述、景别、运镜和台词，点击展开“导演五维决策 / 攻防动作链 / 空间连续性”专业面板。

## Migration Plan

1. 扩展数据模型，确保旧剧集 `storyboard.json` 自动平滑加载；
2. 升级 `AiConstraintEngine` 模板库与任务枚举；
3. 重构 `novel_import_task_service.dart` 提炼流程；
4. 增强 `prompt_assembler.dart` 支持 Seedance / 商用视频 API / H3 多格式导出；
5. 新增 `DirectorValidationEngine` 质检引擎；
6. 调整分镜看板 UI；
7. 执行 `./scripts/deploy_local.sh` 编译并本地发布，比对 md5 确保代码生效。
