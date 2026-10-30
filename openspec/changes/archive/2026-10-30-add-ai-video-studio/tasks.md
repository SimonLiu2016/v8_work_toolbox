## 1. 项目基础结构与数据层

- [x] 1.1 创建 `lib/tools/ai_video_studio/` 目录结构（services/ 和 ui/ 子目录）
- [x] 1.2 在 `lib/services/app_paths.dart` 中添加 `videoStudioDir`、`videoStudioSeriesDir`、`videoStudioGlobalLibDir` 路径常量
- [x] 1.3 实现 `StudioProjectManager`：创建/读取/更新/删除剧集项目（`series_profile.json`），自动创建目录结构
- [x] 1.4 实现 `StudioProjectManager` 的单集 CRUD（`episodes/<ep-id>/storyboard.json`），含原子写入（先写临时文件再 rename）
- [x] 1.5 实现角色资产卡的 CRUD（`characters/<id>/config.json`），包括形态版本列表的读写
- [x] 1.6 实现场景资产卡的 CRUD（`common_scenes/<id>/config.json`）
- [x] 1.7 实现全局公共库的 BGM 和 SFX 索引扫描（读取 `global_library/bgm/` 和 `sfx/` 目录的文件列表并缓存）
- [x] 1.8 在 `lib/tools/registry.dart` 中注册 AI Video Studio 工具

## 2. AI 约束引擎

- [x] 2.1 实现 `AiConstraintEngine` 类，包含任务类型枚举（`scriptBreakdown`/`promptTranslation`/`ideaIncubation`/`titleGeneration`/`bgmRecommend`）
- [x] 2.2 为 `scriptBreakdown` 任务编写 System Prompt 模板：包含景别/时长/情绪基调/台词字数限制约束和 JSON Schema 示例
- [x] 2.3 为 `promptTranslation` 任务编写 System Prompt 模板：中文角色描述 → 英文正/负向 Prompt，包含画风适配逻辑
- [x] 2.4 为 `ideaIncubation` 任务编写 System Prompt 模板：输出 3 个结构化故事方向 JSON
- [x] 2.5 为 `titleGeneration` 和 `bgmRecommend` 任务编写对应 System Prompt 模板
- [x] 2.6 实现 JSON Schema 强制解析与自动 retry（最多 3 次），失败时返回 `ConstraintParseError` 含原始文本
- [x] 2.7 编写 `AiConstraintEngine` 单元测试，验证各任务模板的解析正确性

## 3. Engine Adapter 层

- [x] 3.1 定义 `ImageGenAdapter` 抽象接口（`generate(ImageGenRequest) → Future<File>`）
- [x] 3.2 实现 `SiliconFlowImageAdapter`（硅基流动 Flux-schnell API，含 API Key 配置读取）
- [x] 3.3 实现 `LocalStubImageAdapter`（返回纯色占位图 + 分镜编号文字，供无 API Key 时使用）
- [x] 3.4 定义 `VideoGenAdapter` 抽象接口（`generateVideo(VideoGenRequest) → Future<File>`）
- [x] 3.5 实现 `KenBurnsVideoAdapter`（调用本地 FFmpeg zoompan 滤镜生成 Ken Burns 动效，支持推拉和平移两种模式）
- [x] 3.6 实现 `KlingVideoAdapter`（可灵 I2V API，异步轮询任务状态）
- [x] 3.7 实现 Adapter 工厂，根据工坊设置中配置的 API Key 情况自动选择 Adapter 实现
- [x] 3.8 编写 `KenBurnsVideoAdapter` 集成测试，验证 FFmpeg 可用时生成结果时长和分辨率正确

## 4. Prompt 组装器

- [x] 4.1 实现 `PromptAssembler.buildShotPrompt(shot, character, scene, style, variation)` 方法：拼接全局风格词 + 角色基础 Prompt + 形态差异词 + 场景词 + 运镜词
- [x] 4.2 实现形态差异词合并逻辑（基础 Prompt + variation delta → 完整 Prompt），确保 Prompt 长度不超过目标生图引擎限制（750 词以内）
- [x] 4.3 编写 `PromptAssembler` 单元测试，覆盖多形态合并和长度截断边界

## 5. 异步任务队列

- [x] 5.1 实现通用的 `StudioTaskQueue`：支持入队、状态跟踪（等待/进行中/完成/失败）、取消单任务、并发数配置（默认 2）
- [x] 5.2 集成图像生成任务到队列（`ImageGenTask`），完成后将图片路径写回对应分镜的 `storyboard.json`
- [x] 5.3 集成视频生成任务到队列（`VideoGenTask`），包含轮询云端任务状态和超时处理（默认超时 5 分钟）
- [x] 5.4 编写队列并发控制单元测试，验证最大并发数限制行为

## 6. 声音设计服务

- [x] 6.1 实现 `StudioTtsService`：包装现有 `TtsEngine`，支持多角色批量合成，记录每条音频实际时长（毫秒）
- [x] 6.2 实现 SRT 自动生成逻辑：基于各分镜的累计起始时间和 TTS 时长，输出标准 SRT 文件至 `audio/ep_<id>.srt`
- [x] 6.3 实现 `BgmMatcher`：维护情绪标签 → BGM 文件映射表，支持从全局公共库和 IP 主库分别推荐
- [x] 6.4 编写 SRT 时间轴生成单元测试，验证各分镜时间码累计计算的正确性

## 7. FFmpeg 合成服务

- [x] 7.1 实现 `FfmpegComposer.checkAvailability()`：检测本机 FFmpeg 路径，返回可用状态和版本号
- [x] 7.2 实现 `FfmpegComposer.compose()`：拼接分镜视频片段（支持 dissolve 转场开关）、混入台词音频轨和 BGM 音频轨（含 Ducking 逻辑：台词时段 BGM 降 10 dB）、压制 SRT 字幕，输出 1080×1920 H.264 MP4
- [x] 7.3 实现 Ducking 时间点计算：根据 SRT 时间轴生成 FFmpeg `volume` 滤镜的时间段参数
- [x] 7.4 实现进度解析：从 FFmpeg 的 stderr 解析 `time=` 行并换算为百分比进度通知
- [x] 7.5 编写 `FfmpegComposer` 集成测试：使用测试视频片段和音频，验证输出文件时长与分辨率正确

## 8. 剪映草稿导出器

- [x] 8.1 逆向分析并文档化当前版本剪映 Mac 版草稿 JSON 结构（视频轨、音频轨、字幕轨的关键字段）
- [x] 8.2 实现 `JianyingExporter.export()`：生成完整草稿目录结构（`draft_content.json` + 素材符号链接）
- [x] 8.3 实现字幕轨写入：将 SRT 时间码转换为剪映草稿的字幕时间格式（微秒），写入字幕轨 JSON
- [x] 8.4 实现备用导出：当剪映格式校验失败时，改为输出素材文件夹（视频/音频/SRT 平铺目录），并显示手动导入说明

## 9. 主 UI 框架与剧集库页面

- [x] 9.1 实现 `StudioShell`：三栏布局（左侧资产抽屉 + 中间看板 + 右侧预览播放器），集成到应用工具栏
- [x] 9.2 实现 `ProjectListPage`：展示所有剧集项目列表（名称/制作类型/集数/最近修改），支持新建/删除/进入项目
- [x] 9.3 实现新建剧集项目对话框：输入剧集名称、选择制作类型（三选一 + 类型说明）
- [x] 9.4 实现 IP 主库页面：展示角色卡列表、场景库列表、世界观设定文本编辑区、集数列表
- [x] 9.5 实现角色资产卡编辑界面：名称输入、基准参考图上传、中文描述输入 + "生成 Prompt" 按钮、TTS 音色绑定下拉、形态版本列表管理
- [x] 9.6 实现形态版本编辑界面：形态名称、差异词输入（正向/负向）、形态激活切换
- [x] 9.7 实现前情回顾面板：展示各集剧情摘要，支持手动编辑，显示上集末尾钩子文本

## 10. 创意孵化面板

- [x] 10.1 实现 `IdeaIncubatorPanel`：自然语言输入框 + "生成创意方向" 按钮 + 加载状态
- [x] 10.2 集成 `AiConstraintEngine.ideaIncubation` 任务，展示 3 个结构化故事方向（含主线钩子和分集节奏建议）
- [x] 10.3 实现方向确认逻辑：用户选择某方向后写入 `series_profile.json` 的世界观设定字段，并跳转至 IP 主库页面

## 11. 剧本工坊与分镜看板

- [x] 11.1 实现 `StoryboardBoard`：分镜卡片列表（镜号/景别/情绪/时长/缩略图/对白/Prompt 摘要）
- [x] 11.2 实现"AI 拆分分镜"按钮：将当前集的粗剧情文本提交 `AiConstraintEngine.scriptBreakdown`，将返回的结构化分镜列表写入 `storyboard.json`
- [x] 11.3 实现台词字数校验与"台词过长"警告标记（按 建议时长(秒) × 5 字/秒 计算上限）
- [x] 11.4 实现分镜卡片内联编辑（所有字段可直接点击编辑，离开后 2 秒内触发 Prompt 重组）
- [x] 11.5 实现运镜方案推荐面板（至少 3 个候选方案 + 评分 + AI 推荐高亮），选择后更新分镜 Prompt
- [x] 11.6 实现"单镜 AI 重新生成"：重新调用 AiConstraintEngine，仅更新当前分镜，不影响其他分镜
- [x] 11.7 实现上下集剧情连贯性上下文注入：新建后续集时从剧情记忆库读取前情摘要和上集末尾钩子
- [x] 11.8 实现新集保存时自动提取本集剧情摘要（AI 一句话摘要）并更新剧情记忆库

## 12. 图像与视频生成 UI

- [x] 12.1 实现分镜卡片的生成状态徽章（等待中/生成中/完成/失败 + 重试按钮）
- [x] 12.2 实现"批量生成全集关键帧"：将所有未生成分镜批量入 `StudioTaskQueue`，实时刷新各卡片状态
- [x] 12.3 实现关键帧缩略图（9:16 比例）在分镜卡片中的即时显示（生成完成后无需刷新）
- [x] 12.4 实现分镜视频预览播放器（卡片内嵌循环播放，点击展开全屏）
- [x] 12.5 实现任务队列状态抽屉：展示所有进行中和历史任务，支持取消单任务

## 13. 声音设计面板 UI

- [x] 13.1 实现 `SoundDesignPanel`：分镜台词列表 + 各行的试听按钮 + 批量合成按钮
- [x] 13.2 实现"批量合成全集配音"按钮：调用 `StudioTtsService` 批量合成，完成后更新各行音频时长显示
- [x] 13.3 实现 BGM 推荐面板：点击分镜情绪标签调出 BGM 候选列表（标注情绪类型和来源层级），支持试听和选择
- [x] 13.4 实现简化时序条形图：横向展示台词轨和 BGM 轨各分镜相对位置，宽度与时长成正比

## 14. 合成交付与发布 UI

- [x] 14.1 实现 `DeliveryPanel`：展示各项就绪状态（视频片段/音频/SRT/BGM）+ "导出 MP4" + "导出剪映工程" 按钮
- [x] 14.2 实现 FFmpeg 可用性检测 UI：首次进入工坊时若 FFmpeg 不可用，在页面顶部显示安装引导横幅（含 Homebrew 命令一键复制）
- [x] 14.3 实现 MP4 合成进度条（基于 FFmpeg stderr 解析的百分比进度），完成后显示 Finder 定位按钮
- [x] 14.4 实现"部分分镜未生成"警告对话框，提供"跳过未生成分镜继续合成"和"取消"选项
- [x] 14.5 实现封面帧自动截取与选择（展示至少 5 个候选帧 + AI 评分），选择后支持输入标题文字并预览叠加
- [x] 14.6 实现发布标题候选生成（调用 `AiConstraintEngine.titleGeneration`，展示 3 条风格各异的候选标题）
- [x] 14.7 实现话题标签推荐展示（AI 生成 + 用户可删减）和下集钩子文案生成

## 15. 工坊设置页面

- [x] 15.1 实现工坊设置页：为图像生成/视频生成/TTS 三种能力类型各自提供引擎选择下拉和 API Key 输入框
- [x] 15.2 实现 API Key 的安全存储（写入现有 `KeychainService`）
- [x] 15.3 实现引擎可用性测试按钮（调用 API 发送最小请求验证 Key 有效性），显示通过/失败状态

## 16. 视频下载器集成

- [x] 16.1 在视频下载器的保存路径选择逻辑中，当存在活跃 AI Video Studio 剧集项目时，追加"保存至剧集素材目录"快捷选项
- [x] 16.2 实现选择该选项时的文件复制逻辑（保留原下载目录文件不变），目标路径为当前选定集的 `frames/` 目录
