## Context

现状与约束（动机见 proposal.md — Why，行为契约见 specs/）。

**协议事实**（来自 Agnes 官方文档，中国站）：
- Base URL：`https://api.agnes-ai.cn/v1`，Bearer 认证，OpenAI 兼容。
- 视频创建：`POST /v1/videos`，响应含 `id` / `task_id` / `video_id` 三个字段——**查询要用 `video_id`**，`id`/`task_id` 只是任务标识。
- 视频查询：`GET /agnesapi?video_id=<id>&model_name=<model>`。文档明确：纯 `video_id`（不带 model_name）**只适用 mode=text**；keyframe 与 reference 模式必须带 model_name。当前实现优先试 `/v1/videos/<id>`（OpenAI Videos 标准端点），失败才回落 `/agnesapi`——顺序与文档推荐相反，且 keyframe 模式下标准端点可能返回 200 但内容不可用。
- 状态字段：`status` ∈ queued / in_progress / completed / failed；`progress` 0–100；完成后视频地址在**顶层 `url`**。`internal_status` / `internal_progress` 是内部字段，文档明确不得用于判定。
- 错误码：400 参数问题、401/403 权限、404 video_id 不存在、429 限流、500 服务端。
- 型号限制：`agnes-video-2.5-flash` 的 size 固定 `"720P"`、不支持 videos 参考、images 最多 5 张；`agnes-video-2.5` 支持 720P/1080P/1K/2K、images 最多 8 张、可含首尾帧。
- 计费：按输出秒数 × 分辨率单价计费，**任务一旦创建即计费**——这正是"积分扣了却没拿到视频"不可接受的原因。

**代码现状**：
- `AgnesVideoAdapter`（`video_gen_adapter.dart:875`）单次轮询总预算固定 5 分钟（`_pollTimeout`，同文件 942 行），间隔 3 秒，超时即抛 `StateError`。同文件的 `KlingVideoAdapter`、`SenseAudioVideoAdapter` 同样 5 分钟。
- 查询路径顺序与文档相反（见上），且 `_extractStatus` / `_extractProgress` / `_extractVideoUrl` 是从 `data` 嵌套里读的（`SenseAudioVideoAdapter` 的静态方法），与 Agnes 顶层字段的实际形态不符。
- `video_id` 从不落盘：`generateVideo` 是纯内存过程，`SegmentVideoGenTask`（`studio_generation_tasks.dart:284`）调完即结束，任务失败后没有任何残留线索。
- `StudioTaskQueue`（`studio_task_queue.dart`）是纯内存队列，无持久化，重启即清空。
- `MediaModelCapability.forModel`（`media_capability.dart:535`）把 `agnes-image-2.5-flash` 与 `agnes-video-2.5-flash` 映射到同一条 `agnesVideo` 声明。
- `ai_config_page.dart:1294` 的 Agnes chip 预填中转站 IP `http://119.29.249.154:3356` 与 `deepseek-chat, gpt-4o-mini`。

**约束**：
- 台账必须是本地文件存储——`StudioTaskQueue` 的内存模型不动，台账是它下面新的一层。
- 不改变 `VideoGenAdapter` 接口签名（`generateVideo` 返回 `Future<File>`）——那是四个适配器 + 规整包装器 + 两类任务共用的契约。台账的挂载点放在适配器内部与任务恢复入口，不上升到接口。
- 供应商返回的 `url` 是临时地址，取回必须立即下载。

## Goals / Non-Goals

**Goals:**
- Agnes 视频任务的生命周期（创建 → 排队 → 生成 → 取回）在本地有完整、可恢复、可追溯的记录。
- 超时从"判定失败并丢弃"改为"保留并允许继续"，消除积分损失。
- 轮询协议与 Agnes 文档一致（查询路径、字段位置、内部字段忽略、429 退避）。
- Agnes 快速填充预设填真实地址与真实模型。
- Agnes 全型号能力声明按型号分档，图像与视频分离。

**Non-Goals:**
- 不改 `VideoGenAdapter` 接口、不改 `StudioTaskQueue` 的内存调度模型、不改 `SegmentVideoGenTask` 的产物写回逻辑。
- 不为 Kling / SenseAudio / Dola 做台账——它们留在本次范围外，但台账的数据结构 SHALL 按供应商中立设计，使后续接入不必改表结构。
- 不做跨设备同步、不做云端台账。
- 不实现 Agnes 的 reference 模式多图/音频/视频参考（当前适配器只用 keyframe 与 text 两种模式）；能力声明会如实记录 reference 的上限，但适配器不必在本变更内支持它。

## Decisions

### 决策 1：台账是独立文件层，不塞进 StudioTaskQueue

`StudioTaskQueue` 的 `StudioTask` 是可变的进度快照（注释明言：不可变对象 + copyWith 会让 FFmpeg 每秒十几次回调重建一串对象）。把持久化塞进去会让每次进度回调都触发写盘。

台账只记**生命周期事件**（创建、状态变化、完成、失败、放弃），不记进度快照。写入时机是离散的状态跃迁，一个视频任务整个生命周期最多十几次写盘。

备选：给 `StudioTask` 加 `toJson` 并定时全量落盘。否——它没有稳定的序列化边界（`adapter` 字段不可序列化），且会把内存模型的性能特征暴露给磁盘。

### 决策 2：台账按「供应商中立的视频任务」建模，不按 Agnes 建模

表结构用 `providerId` / `model` / `remoteTaskId` / `status` / `context`（关联键）/ `targetPath` 等通用字段，Agnes 特有的 `video_id` 语义（区别于 `task_id`）收在 `remoteTaskId` 一处——文档说查询要用 `video_id`，那就存 `video_id`。供应商特有字段放 `extra` 自由映射，不加 Agnes 专属列。

理由：spec 要求"重启不重复创建"，这条对所有异步视频供应商都成立；Kling 与 SenseAudio 后续接入时直接复用表结构，只是多一个 `providerId` 的取值。

备选：做成 `AgnesVideoTaskLedger`。否——名字会把第二个供应商逼进第二次重构。

### 决策 3：超时预算拆两段，阶段由云端状态切换推断

排队预算（默认 10 分钟）+ 生成预算（默认 15 分钟）。云端 `status` 从 `queued` 变为 `in_progress` 的时刻即阶段切换点——这是唯一可靠的推断依据，因为 Agnes 不返回"预计开始时间"。

两段都耗尽而任务未完成 → 状态置为 `cloudProcessing`（云端仍在处理），**不是 failed**。用户可"继续等待"（重新计一段预算继续轮询）或复制 remoteTaskId。

备选：单段 30 分钟固定预算。否——它把"排队久"和"生成慢"混为一个数，用户无法根据实际瓶颈调整；且一个 30 分钟的静默等待没有任何阶段反馈。
备选：用视频时长推算生成预算（如 秒数 × 3）。否——实测数据出现前，任何倍数都是编造；文档没给生成耗时区间。

### 决策 4：恢复入口挂在适配器构造后、任务提交前

`AgnesVideoAdapter` 持有一个可选的台账引用。`SegmentVideoGenTask.run` 提交前不做事；恢复由独立入口负责——`StudioProjectManager` 或 AppShell 启动时扫描台账，对 `cloudProcessing` / `polling` 状态的任务重建轮询，取回后走 `manager.saveEpisode` 写回原路径。

轮询循环本身从 `generateVideo` 中抽出为可独立调度的 `_pollUntilDone`，恢复路径复用它，不复制第二份轮询逻辑。

备选：在 `generateVideo` 内部先查台账再决定是否创建。否——那会让"恢复"和"生成"两条控制流挤在一个方法里，而它们的安全点、取消语义、错误处理都不同。

### 决策 5：查询路径以 /agnesapi 为主，标准端点降为兜底

按文档推荐，主查询用 `GET /agnesapi?video_id=...&model_name=...`；若该路径不可用（非 Agnes 供应商走同一适配器时）才回落 `/v1/videos/<id>`。

同时修正字段读取：Agnes 的 `status`/`progress`/`url` 在**顶层**，不在 `data` 下。现有代码复用 `SenseAudioVideoAdapter._extractStatus` 等从 `data` 读的静态方法，与 Agnes 响应形态不符——这是"状态明明是 completed 却取不到视频"的潜在原因之一，本次一并修正。

备选：保持现有顺序，只加长超时。否——顺序反了时 keyframe 模式可能从标准端点拿到 200 但字段位置不同，读取失败会让轮询空转到超时。

### 决策 6：能力声明按型号分档，图像视频分离

`forModel` 增补 `agnes-video-2.5`、`agnes-image-2.0-flash`、`agnes-image-2.1-flash`、`agnes-image-2.5-flash` 四条独立声明；`agnes-image-2.5-flash` 不再命中 `agnesVideo`。

`agnes-video-2.5-flash` 的 `resolutions` 收窄为 `['720p']` 并标注 `isDeclared: true`；`agnes-video-2.5` 为四档。图像三条声明的尺寸能力同族，但仍是三条独立声明（型号 id 是用户配置里实际出现的字符串）。

备选：只修 `agnes-video-2.5-flash` 一条，其余留给用户手工踩坑。否——spec 的"同族型号按限制分档"正是本次要立的规则，留着不落实等于没写。

## Risks / Trade-offs

- **[台账文件损坏或并发写入]** → 单文件 + 写入前落临时文件再 rename（与 `novel_chapter_storage` 的原子写入同一套做法）；所有写操作串行化（队列内单线程），不与 UI 线程争。损坏时以降级为空台账启动并记录日志，MUST NOT 阻断应用启动。
- **[轮询恢复与用户手动重试叠加，产生两次下载]** → 台账状态机保证同一 remoteTaskId 只有一个活跃轮询者；恢复入口对已处于 `polling` 状态的条目跳过。
- **[云端任务在用户放弃后仍在计费]** → 台账明确记录"放弃"只意味着本地不再等待，不改写云端状态；UI 文案 SHALL 说明这一点，并提供控制台链接与 remoteTaskId 复制。**本地无法取消云端任务**（Agnes 文档未提供取消端点），这一点必须在 UI 明说，不能让用户以为点取消就停止计费。
- **[10+15 分钟仍不够极端排队]** → 预算可调，且"继续等待"可无限次追加；同时 UI 显示当前所处阶段（排队中/生成中）与已等待时长，用户能判断是继续还是放弃。
- **[预填模型列表随 Agnes 上下架过期]** → 预填值是静态字符串，必然过期；缓解是把型号集中在一处常量（而不是散在 chip 回调里），后续更新只改一处。这不能根治，只是降低维护成本。
- **[改动触及三个适配器共用的静态方法]** → `_extractStatus` 等是 `SenseAudioVideoAdapter` 的静态方法，被 Agnes 适配器复用。修正 Agnes 的字段读取时 SHALL 新增 Agnes 专用的读取函数，不改动 SenseAudio 的那几个——否则会改掉一个正在工作的供应商的行为。

## Migration Plan

无数据迁移（台账是新文件，能力声明是内存常量，预填是 UI 字符串）。部署顺序：

1. 能力声明补齐（`media_capability.dart`）——纯增量，无行为回归风险。
2. Agnes chip 预填修正——独立小改动，可单独验证。
3. 台账层（新增文件 + `app_paths.dart` 加目录）——新增代码，不影响既有路径。
4. 适配器改造：查询路径与字段修正 → 轮询循环抽出 → 台账接入 → 两段预算。
5. 恢复入口接线。
6. 设置项（排队/生成预算）。

回滚：各部分可独立回滚；台账文件留着无害（无对应代码时它只是个不被读的文件）。

验证要点：用一个真实 Agnes 任务走完"创建 → 杀掉应用 → 重启 → 取回"全流程；确认杀掉重启后没有第二次创建请求（看 Agnes 控制台的调用记录）。
