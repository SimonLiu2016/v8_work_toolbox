## Why

当前的“短视频工坊”在面对小说文本处理与分镜生成时存在严重的断层问题：小说长文本被一次性暴力压缩为极短粗大纲导致 90% 的视听细节与台词信息蒸发；分镜拆解跳过了“导演调度层”，缺乏五维决策（物理动势、空间光影、光学机位、时间演变、美学质感）；打斗与动作分镜缺乏攻防因果链，退化为回合制假动作；连续性台账缺乏空间地标坐标与动态末态（支撑脚/速度/动势）支持。通过引入并整合工业级 `modular-drama-director` 体系，打通“小说解构与保护清单 → 剧本场次与节拍 → 五维导演决策与动作编舞 → 空间与动态末态台账 → 平台多通道编译与可执行性审计”的端到端完整闭环，从根本上解决小说影视化分镜生硬、空间混乱与动作打不起来的行业痛点。

## What Changes

- **新增** `ai-video-studio/drama-director-engine` 核心能力：
  - 五维导演决策矩阵：主体与物理动势、环境与主光源世界方向、光学摄影机四段式调度、真实读时与状态演变、美学介质渲染；
  - 动作与战斗专项编舞引擎：Combat DNA、六步攻防因果链（意图→动作→交互→受力→位移→接力）、3~4 招连续接力攻击组、镜头职责划分，彻底消除回合制空洞打斗；
  - 空间底图与地标坐标体系：解耦机位画面位置与世界真实坐标，引入 180° 摄影轴线管理；
  - 平台级提示词编译引擎：专有即梦 Seedance（任务化执行稿 + 剪辑接力边 Handoff）、主流商业视频（可灵 / Runway / CogVideo 自然语言摄影四段式）、H3 / 剪映数据对接；
  - C01~C09 视频可执行性自动化审计关口：针对时长负荷、攻防因果、空间防穿帮、光影一致性与资产引用的自动化前置校验。
- **修改** `ai-video-studio/novel-import`：
  - 从单一大纲提炼，重构为“IP主库解构 + 剧本场次节拍（Scenes & Beats）提炼”；
  - 引入“事实与核心对白保护清单（Protected Facts & Utterances）”，区分硬事实、合理推断与导演选择，原著关键金句独立登记锁定，禁止生成阶段篡改或遗失。
- **修改** `ai-video-studio/script-workshop`：
  - 数据模型支持 `Scene / Beat` 层级并向下映射为生成片段与具体分镜；
  - 升级 `scriptBreakdown` 提示词库与解析 Schema，全面注入五维导演决策参数与切镜动机依据。
- **修改** `ai-video-studio/shot-continuity`：
  - 扩展连续性台账模型，从静态手持物/光影升级为支持**动态末态（Dynamic Exit States）**：速度矢量、角动量、支撑脚平衡、动作未完成相位；
  - 建立镜头与片段间的动态共享锚点接力机制。
- **升级** UI 交互与看板：
  - 任务抽屉与分镜看板支持展示场次节拍、保护清单、攻防动作链和运镜动机。

## Capabilities

### New Capabilities
- `ai-video-studio/drama-director-engine`: 负责短视频工坊的五维导演决策系统、动作专项编舞（Combat DNA / 六步攻防链）、空间站位与地标坐标管理、多平台（即梦Seedance/可灵/Runway/H3）提示词编译以及 C01~C09 视频可执行性自动化审计关口。

### Modified Capabilities
- `ai-video-studio/novel-import`: 重构小说导入管线，新增剧本场次与节拍（Scenes & Beats）提炼，新增核心对白与原著事实保护清单（Protected Facts & Utterances）。
- `ai-video-studio/script-workshop`: 引入 Scene/Beat 层级，在拆镜与单镜生成中强制注入五维导演决策与切镜动机。
- `ai-video-studio/shot-continuity`: 升级连续性台账，支持空间地标绝对坐标、180° 轴线管理及包含速度/支撑脚/动势的动态末态继承。

## Impact

- **数据模型**：扩展 `lib/tools/ai_video_studio/models/studio_models.dart`，新增 `drama_director_contract.dart`，升级 `StudioShot`、`StudioEpisode` 与 `ShotContinuity`，保证向后兼容老版本 JSON。
- **服务层**：重构 `novel_import_task_service.dart`、`ai_constraint_engine.dart`、`prompt_assembler.dart`，新增 `director_validation_engine.dart`。
- **UI 层**：更新 `storyboard_board.dart`、`novel_task_drawer.dart` 与 `delivery_panel.dart`，直观透出导演决策信息与多平台编译结果。
- **依赖与构建**：纯 Dart / Flutter 架构实现，无需额外外部 Python 环境依赖；代码完成后由 `./scripts/deploy_local.sh` 统一构建验证。
