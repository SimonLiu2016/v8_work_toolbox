## 1. 数据模型与契约升级 (Models & Presets)

- [x] 1.1 在 `StudioSeries` 中增加 `defaultAspectRatio` 与 `defaultResolution`，并更新 `toJson`、`fromJson`、`copyWith`
- [x] 1.2 在 `StudioShot` 中增加 `videoMode`、`videoPrompt`、`aspectRatio`、`resolution`，并更新 `toJson`、`fromJson`、`copyWith`
- [x] 1.3 在 `StudioPromptTemplate` 中补齐全链路 8 套核心 AI 编剧与导演流水线系统提示词出厂预置
- [x] 1.4 在 `StudioPresetStore` 中支持全链路模板分类管理与有效内容动态查询注入

## 2. 视频提示词纯净化与正向全员闭口守卫 (PromptAssembler)

- [x] 2.1 改造 `PromptAssembler.buildVideoGenPrompt`：彻底废弃中括号内心独白标记，点名所有在场角色注入“全员闭口与画外心声守卫”强正向指令
- [x] 2.2 在 `PromptAssembler.buildVideoGenPrompt` 中增加确定性规则过滤：丢弃单镜无效的 180° 轴线标记，消除推拉运镜与定机位的互斥冲突，消解场景与地标冲突

## 3. AI 约束引擎与拆镜视听铁律 (AiConstraintEngine)

- [x] 3.1 改造 5D 导演拆镜提示词 `_promptScriptBreakdown5D`，注入 5 大视听语法严苛约束（单镜单一动作、主体聚焦、运镜排他、微表情递进、景别交替）
- [x] 3.2 实现 `StudioAiTask.videoPromptRewrite` 提示词消解重写 AI 任务及 Schema 解析
- [x] 3.3 实现 `AiConstraintEngine.autoFixAuditIssues` 导演质检 AI 一键自愈与修复服务
- [x] 3.4 改造 `AiConstraintEngine.systemPromptFor`，全面优先读取 `StudioPresetStore` 用户自定义内容
- [x] 3.5 在 `director_validation_engine.dart` 中增加 C10 规则（动作过载与运镜互斥审计）

## 4. 视频生成任务流水线解耦与模式参数分流 (Generation Pipeline)

- [x] 4.1 改造 `studio_generation_tasks.dart` 的 `generateShotKeyframeTask`：根据分镜/剧集比例与分辨率动态推导宽高像素，彻底废除写死 1080x1920
- [x] 4.2 改造 `studio_generation_tasks.dart` 的 `generateShotVideoTask`：根据 `shot.videoMode` 严格分流参数（`keyframe` / `reference` / `text` 互斥），注入 `ratio` 与 `sizeTier`
- [x] 4.3 改造 `video_gen_adapter.dart` 的 `AgnesVideoAdapter`，确保 `keyframe`、`reference`、`text` 准确映射 Agnes API 入参且不传递冲突字段

## 5. UI 交互界面增强 (UI & Boards)

- [x] 5.1 改造 `series_page.dart` 剧集设定面板：增加默认画幅比例（9:16 / 16:9 等）与默认分辨率可视化选择器
- [x] 5.2 改造 `storyboard_board.dart` 分镜卡片与详情抽屉：增加视频生成模式切换（Auto / Keyframe / Reference / Text），提供 AI 提示词重写入口
- [x] 5.3 改造 `storyboard_board.dart` 质检弹窗：增加“一键 AI 自动修复全案分镜”与单镜 AI 修复交互按钮

## 6. 验证与工程部署 (Verification & Deploy)

- [x] 6.1 编写单元测试验证：多模式参数分流、全员闭口正向守卫、比例分辨率换算、提示词冲突消解与质检 C10 规则
- [x] 6.2 运行静态检查 `flutter analyze` 与全套相关测试
- [x] 6.3 按照工程级核心规范执行 `./scripts/deploy_local.sh` 编译 Release 并替换本机应用
