## 1. 数据模型与底层基础设施升级

- [x] 1.1 在 `studio_models.dart` 中为 `StudioEpisode` 增加文学剧本相关字段（`screenplayText`、`DramaScene` 增强结构），支持旧数据平滑向下兼容
- [x] 1.2 在 `studio_models.dart` 中为 `StudioShot` 扩展首尾帧路径字段（`firstFramePath`、`lastFramePath`）
- [x] 1.3 在 `drama_director_contract.dart` 中为 `ContinuityLedger` 增加视线朝向（`gazeDirection`）与机位轴线侧（`cameraAxis`）支持
- [x] 1.4 在 `studio_shell.dart` 中为 `StudioStage` 注入 `screenplay('screenplay', '剧本工作台', Icons.auto_stories_outlined)`，更新工序导航路由

## 2. 约束引擎放开与动态时长/动作拆分

- [x] 2.1 修改 `ai_constraint_engine.dart` 中的分镜建议时长校验，解除 3.0~5.0 秒硬门槛，升级为 4.0~12.0 秒自适应动态范围
- [x] 2.2 更新 `ai_constraint_engine.dart` 中的拆镜提示词模板与 JSON Schema，声明 4~12 秒时长指导规则
- [x] 2.3 在拆镜算法中加入台词语速换算引擎（按 4~5 字/秒基准 + 气口余量动态计算 `duration_sec`）
- [x] 2.4 在 `ai_constraint_engine.dart` 中加入复合动作过载检测与智能分拆逻辑，禁止单镜头挤压 3 个以上独立物理动作

## 3. 多角色同框与图像参考图全要素注入

- [x] 3.1 改造 `PromptParts`，由单角色扩展为支持多角色列表 `List<CharacterCard>` 与形态覆盖字典
- [x] 3.2 重构 `storyboard_board.dart` 中的 `_enqueueFrame` 逻辑，解除只取 `characterIds.first` 的限制，全量收集同框角色
- [x] 3.3 重构 `studio_generation_tasks.dart` 中的 `ImageGenTask._referenceImages`，提取分镜内所有关联角色的定妆图/三视图
- [x] 3.4 优化 `prompt_assembler.dart` 中的角色提示词拼接，自动输出多角色的主客体构图位置描述（如前景/背景/左右侧）
- [x] 3.5 确保 Agnes Image 等图像生成适配器将所有角色的参考图全量送入 `extra_body.image`

## 4. 视频生成 Prompt 组装与声画一体改造

- [x] 4.1 在 `prompt_assembler.dart` 中实现专门的 `buildVideoGenPrompt` 方法，独立于纯生图提示词
- [x] 4.2 组装结构化对白发声口令（格式如：`[角色对白发声]: 姜七夜大声说道：“余小白，我迟早得叫你姐夫！”（语气：戏谑，口型同步）`）
- [x] 4.3 组装环境光影、5D 导演决策、物理动势与摄影运镜轨迹到视频提示词中
- [x] 4.4 修改 `studio_generation_tasks.dart` 中 `VideoGenTask.run`，将组装好的声画全要素提示词传入 `VideoGenRequest.promptZh`，彻底替代纯英文生图提示词
- [x] 4.5 确保 `video_gen_adapter.dart` 将分镜的动态时长（4~12s）准确透传给 Agnes 视频 API

## 5. 影视文学剧本创作工作台开发

- [x] 5.1 创建 `ScreenplayPanel`（`lib/tools/ai_video_studio/ui/screenplay_panel.dart`）核心组件与界面布局
- [x] 5.2 实现影视分场管理界面（场号、日景/夜景、内景/外景、地点、出场角色标签）
- [x] 5.3 实现场次动作节拍与台词编辑卡片，支持实时静态动作过载预警
- [x] 5.4 接入 AI 剧本生成引擎：支持从「创意孵化」故事大纲或小说章节一键生成标准分场剧本
- [x] 5.5 实现剧本一键转换为 5D 分镜看板能力，将分场动作与对白精准注入分镜列表

## 6. 首尾帧接力生成与镜头连贯性增强

- [x] 6.1 在 `ffmpeg_composer.dart` 中实现视频最后一帧抽取工具方法（`extractLastFrame`）
- [x] 6.2 在 `VideoGenTask` 中实现连续镜头首尾帧接力：当前后镜头连续时，自动提取前镜尾帧作为后镜首帧 `first_frame`
- [x] 6.3 在连续性状态更新中维护 180 度轴线，防止同场对话对白镜头发生跳轴穿帮
- [x] 6.4 将前镜末尾的动势相态（`dynamicExitState`）注入后镜起始物理条件

## 7. 分镜看板交互优化与媒体预览/下载支持

- [x] 7.1 解耦分镜看板中单镜重新生成与大段生成的加载状态，单镜重新生成仅局部刷新该分镜指示器，避免多卡片同时转圈
- [x] 7.2 明确分镜看板中片段大段（视频渲染单元）与单镜卡片的功能标识与操作区分
- [x] 7.3 在分镜看板与资产库中为图片卡片增加放大查看模态框与保存/下载到本地功能
- [x] 7.4 在分镜看板中为视频卡片提供全屏播放预览与右键/按钮另存为本地 MP4 文件功能

## 8. 端到端验证与工程级构建部署

- [x] 8.1 运行单元测试验证 `ai_constraint_engine`、`prompt_assembler`、`studio_models`
- [x] 8.2 验证第 5 镜对白发声提示词组装包含姜七夜、余小白两位角色参考与对白发声指令
- [x] 8.3 严格遵循 `GEMINI.md` 规则执行 `./scripts/deploy_local.sh` 编译并替换本机应用
- [x] 8.4 启动应用验证剧本工作台新建、生成、转分镜及分镜声画视频生成完整闭环
