## Why

当前“AI 漫剧短视频工坊”在分镜生成与视频合成环节存在多项关键缺陷与灵活性瓶颈：
1. **视频生成模式（Mode）硬编码**：当前所有视频生成请求被一刀切强制指定为 `keyframe` 模式，无法针对纯文本大动作、多角色参考图或环境空镜按需切换为 `text` 或 `reference` 模式，且用户在看板中无法手动选择；
2. **视频提示词严重冲突与指令过载**：原样堆叠字段导致场景冲突（地牢 vs 衙门口）、光影矛盾（黄昏残阳 vs 地牢火把）、运镜互斥（缓慢推进 vs 定机位）、情绪矛盾（温馨 vs 阴冷残阳）以及 180° 轴线无效过载，模型极易生成崩坏视频；
3. **分镜动作过密与视听节奏单一**：AI 拆镜缺乏单镜单一动作、主体聚焦、运镜排他与景别起伏的强约束；
4. **多人同框心声指令穿帮**：带括号的内心独白机器标记被误判为对白，导致非主角在视频中张嘴念出主角的心声独白；
5. **AI 系统提示词全流程缺乏配置入口**：小说转剧集、剧集转剧本、剧本转分镜等关键 AI 环节提示词写死在代码内，无法针对不同题材流派自由微调；
6. **画幅比例与分辨率写死**：生图固定写死 1080x1920，视频固定写死 9:16 720P，缺少剧集级默认横/竖屏（如 16:9 / 9:16）与分辨率（1K/2K/4K/720P/1080P）设置，分镜也无法自适应或覆盖。

## What Changes

- **多模式视频生成路由与看板控制**：`StudioShot` 增加 `videoMode`（`auto`、`keyframe`、`reference`、`text`），分镜看板支持可视化下拉切换；根据镜头特征智能路由，严格按 Agnes 官方规范分流素材参数（keyframe 仅传首尾帧，reference 仅传 images，text 纯文本）。
- **AI 视频提示词消解重写与正向画外音守卫**：实现 `StudioAiTask.videoPromptRewrite` 任务，自动过滤矛盾光源、消除冲突机位；彻底废除 `[角色内心独白/心声]` 标记，显式注入全员闭口正向守卫（主角与同框配角嘴唇全程闭合严禁开口）。
- **AI 拆镜五大视听铁律约束**：在 5D 导演拆镜提示词中严厉注入“单镜单一动作律”、“主体聚焦律”、“运镜互斥律”、“微表情递进律”与“视听景别交替律”。
- **导演质检报告 AI 一键修复工具箱**：扩展 C10（动作过载与运镜互斥）规则，在质检报告弹窗中增加“一键 AI 自动修复全案分镜”与单镜快捷修复能力。
- **全链路 AI 系统提示词可配置化**：将全流程 8 套核心 AI 提示词注册入 `StudioPresetStore`，在“预设与提示词管理”对话框中支持查看、编辑修改、Diff 对比与一键恢复出厂。
- **剧集默认与分镜覆盖的画幅比例/分辨率体系**：`StudioSeries` 增加 `defaultAspectRatio` 与 `defaultResolution`；`StudioShot` 支持局部覆盖；任务流水线解耦写死的 1080x1920，全链路贯通横竖屏与 1K/2K/4K/720P 生成。

## Capabilities

### Modified Capabilities

- `ai-video-studio/shot-production`: 扩展分镜视频生成模式（auto/keyframe/reference/text）路由与数据分流、横竖屏比例与分辨率继承/覆盖、以及全员闭口画外心声正向守卫。
- `ai-video-studio/script-workshop`: 5D 导演拆镜系统提示词注入 5 大视听语法严苛约束、提示词冲突消解 AI 重写任务、导演质检 AI 自动修复，以及全链路 AI 系统提示词可配置化。
- `ai-video-studio/series-asset-library`: 剧集主档案持久化默认画幅比例（9:16 / 16:9 / 21:9 等）与默认分辨率档位，在世界观设定中提供可视化配置界面。

## Impact

- **数据模型**：`StudioSeries`、`StudioShot` 扩展序列化字段，向后完全兼容；
- **提示词与生成服务**：`PromptAssembler`、`AiConstraintEngine`、`StudioGenerationTasks`、`AgnesVideoAdapter` 全面贯通多模式与比例参数；
- **UI 界面**：`series_page.dart` 增加比例与分辨率配置；`storyboard_board.dart` 增加模式切换与质检 AI 修复按钮；`studio_preset_management_dialog.dart` 开放全链路 AI 系统提示词编辑。
