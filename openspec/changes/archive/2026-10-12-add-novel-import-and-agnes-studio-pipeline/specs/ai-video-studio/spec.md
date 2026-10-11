## Purpose

Provides end-to-end AI video studio workflows for short dramas, including novel text file ingestion with automatic IP master library extraction, dynamic climax-driven episode segmentation, storyboard breakdown with standardized shot constraints, and seamless integration with Agnes Image and Video generation models via user proxy relay.

## ADDED Requirements

### Requirement: 小说文本文件导入与长文解析
系统 SHALL 支持用户在创意孵化面板中导入本地文本文件（`.txt` 或 `.md` 格式）。导入后系统 SHALL 解析小说内容，通过大模型长文提取管线自动提取并结构化拆解出 IP 主库（世界观设定、角色卡库、场景资产库以及短剧分集与前情钩子）。

#### Scenario: 成功导入小说并填充 IP 主库
- **WHEN** 用户在创意孵化面板选择并上传一部小说文本文件
- **THEN** 系统解析文本并自动生成世界观、主要角色卡（含中英文 Prompt）、常驻场景卡及推荐的分集大纲，并自动持久化写入本地剧集存储目录

#### Scenario: 导入无效或空文件
- **WHEN** 用户导入空文件或非纯文本内容
- **THEN** 系统展示明确的可操作错误提示并允许用户重新选择文件

### Requirement: 剧情高潮驱动的短剧分集与前情生成
系统 SHALL 根据原著故事的主线冲突节点与高潮情绪峰值，自动推荐划分短剧集数（单集对应 1~2 分钟短剧体量）。系统 SHALL 为每一集生成结构化大纲（`synopsis`）、前情记忆摘要（`summary`，控制在 200 字以内）以及集尾悬念钩子（`hook`），并将相邻集之间的剧情链条连贯注入。

#### Scenario: 自动划分集数并生成连贯前情
- **WHEN** 系统执行小说分集拆解
- **THEN** 系统输出 N 个分集条目，每个条目均包含标题、粗大纲、精炼前情与集尾钩子，首集的开头具备冲突爆点，各集尾部具备悬念转折

### Requirement: 分镜看板结构化拆解与硬约束规范
系统 SHALL 将单集剧本大纲拆解为结构化分镜列表。每个分镜 SHALL 包含四个强制字段：镜号（`number`，连续递增）、景别（`shotSize`，涵盖远景、全景、中景、近景、特写五类）、画面描述（`actionZh`，严格控制在 30 到 50 字之间，且遵循【主体 + 动作 + 环境】微动作具象化规则）、台词/旁白（`dialogue`，标注预估秒数与配音情绪指令）。每个分镜的建议时长（`durationSec`）SHALL 严格限定在 3 到 5 秒之间。

#### Scenario: 分镜拆解符合四字段与时长约束
- **WHEN** 用户对某集执行 AI 分镜拆解
- **THEN** 系统返回的分镜列表中所有分镜时长均在 3~5 秒之间，画面描述字数在 30~50 字之间，景别标注准确，台词标注预估秒数

#### Scenario: 景别包含全景选项
- **WHEN** 用户查看或编辑分镜的景别下拉框
- **THEN** 景别选项完整呈现“远景”、“全景”、“中景”、“近景”、“特写”供选择与保存

### Requirement: 分镜看板双模式逐步拆解
系统 SHALL 在分镜看板中同时支持两种拆解模式：单集即时拆解（针对当前选中的特定剧集执行生成）与一键全剧批量流水线拆解（按集数串行自动推进全剧所有集的分镜拆解，并将上一集的实际生成摘要作为前情记忆注入下一集）。拆解完成后，分镜的关键帧图片与视频片段状态 SHALL 默认为待生成（`pending`）。

#### Scenario: 单集即时拆解
- **WHEN** 用户在分镜看板点击“AI 拆解本集分镜”
- **THEN** 系统仅对当前选中的集数执行拆解，生成结构化镜头列表并即时渲染到看板卡片

#### Scenario: 一键全剧批量拆解
- **WHEN** 用户点击“批量拆解全部分镜”
- **THEN** 系统显示全剧进度条，逐集串行调用拆解任务并持久化，完成后通知用户审阅

### Requirement: 中转站 Agnes Image 2.5 Flash 图像生成适配
系统 SHALL 在图像生成适配层自适应支持 `agnes-image-2.5-flash` 模型。当使用该模型时，系统 SHALL 发送符合供应商规范的请求体：`size: "2K"`，`ratio: "9:16"`，`extra_body.response_format: "url"`。当分镜关联角色存在定妆参考图时，系统 SHALL 将其作为公共 URL 或 Data URI 传入 `extra_body.image` 数组中。

#### Scenario: 成功调用 Agnes Image 生成关键帧
- **WHEN** 任务队列执行关键帧生图任务且当前系统图像模型为 `agnes-image-2.5-flash`
- **THEN** 系统向中转站 `/v1/images/generations` 发送包含 2K 与 9:16 参数的请求，成功下载返回的图片 URL 并保存为本地分镜首帧图片

### Requirement: 中转站 Agnes Video 2.5 Flash 视频生成适配
系统 SHALL 在视频生成适配层提供对 `agnes-video-2.5-flash` 的完整集成。系统 SHALL 向中转站 `POST /v1/videos` 发起任务创建请求（参数包括 `model: "agnes-video-2.5-flash"`, `mode: "keyframe"`, `size: "720P"`, `aspect_ratio: "9:16"`, `seconds: "5"`, `first_frame: "<图片URL/DataURI>"`），并异步轮询 `/agnesapi?video_id=...` 或 `/v1/videos/{id}`，直到状态为 `completed` 后自动下载成片 MP4 到本地。

#### Scenario: 成功调用 Agnes Video 生成 5 秒视频片段
- **WHEN** 用户或队列针对已有关键帧的分镜触发视频生成
- **THEN** 系统向中转站创建视频生成任务并轮询进度，任务完成后将成片 MP4 保存至分镜对应目录并将分镜状态标记为已完成
