## 1. Agnes 供应商预设修正

- [x] 1.1 `lib/shell/ai_config_page.dart`：将「Agnes / 中转站 (视/图多模态)」chip 标签改为「Agnes」，供应商名称预填由「Agnes (中转站)」改为「Agnes」
- [x] 1.2 同处：Base URL 预填改为 `https://api.agnes-ai.cn/v1`，移除中转站 IP `http://119.29.249.154:3356`
- [x] 1.3 同处：文本模型预填改为 Agnes 在售型号（agnes-2.5-flash / agnes-2.5-pro / agnes-3.0-flash / agnes-3.0-pro），移除 `deepseek-chat, gpt-4o-mini`
- [x] 1.4 同处：图像模型预填改为 `agnes-image-2.0-flash, agnes-image-2.1-flash, agnes-image-2.5-flash`；视频模型预填改为 `agnes-video-2.5, agnes-video-2.5-flash`
- [x] 1.5 将 Agnes 型号字符串集中为 `AgnesPreset` 常量类（不再散落在 chip 回调里），后续上下架只改一处
- [x] 1.6 确认预填守卫不变：仅当 URL 为空或指向 openai.com 时才覆盖，不改写用户已填地址

## 2. Agnes 能力声明补齐

- [x] 2.1 `lib/services/media_capability.dart`：为 `agnes-video-2.5` 增加独立能力声明——时长 4–12、分辨率 720P/1080P/1K/2K、支持首帧与尾帧、reference 模式最多 8 张参考图
- [x] 2.2 同处：将 `agnes-video-2.5-flash` 的 resolutions 收窄为 `['720p']`（文档：size 必须为 720P），并注明不支持 videos 参考、images 最多 5 张
- [x] 2.3 同处：新增 `agnes-image-2.0-flash` / `agnes-image-2.1-flash` / `agnes-image-2.5-flash` 三条图像能力声明（size 1K/2K/3K/4K，ratio 含 9:16）
- [x] 2.4 同处：修正 `forModel`——图像型号不再命中 `agnesVideo`，三个型号各自命中自己的声明；未知 agnes-* 型号返回 null 走协议默认并显示「未经确认」
- [x] 2.5 为能力声明补测试：flash 型号查询结果 resolutions 恰为 `['720p']`；图像型号查询结果不含视频字段 → 落在 `test/tools/ai_video_studio/video_task_ledger_test.dart` 的「Agnes 能力声明分档」组（5 条断言，含图像不继承视频能力）

## 3. 视频任务台账

- [x] 3.1 `lib/services/app_paths.dart`：新增视频任务台账存储路径（`AppPaths.videoTaskLedgerFile` / `videoTaskLedgerDir`，已登记进 `allDirs`）
- [x] 3.2 新增 `lib/tools/ai_video_studio/services/video_task_ledger.dart`：供应商中立的任务台账——字段含 providerId、model、remoteTaskId、status、context（seriesId/episodeId/segmentId 或 shotNumber）、targetPath、createdAt、lastStatus、lastProgress、error；remoteTaskId 存 Agnes 的 `video_id`
- [x] 3.3 同文件：写入采用「临时文件 + rename」原子写，所有写操作串行化；文件损坏时降级为空台账并记日志，MUST NOT 阻断应用启动
- [x] 3.4 同文件：状态机含 polling / cloudProcessing / completed / failed / abandoned；保证同一 remoteTaskId 同时只有一个活跃轮询者（record 先去重，_active 集合防重复认领）
- [x] 3.5 同文件：查询 API——pendingEntries / allEntries / findByRemoteId / findByLocalId / update / remove / prune
- [x] 3.6 为台账补测试：创建即落盘、进程重启后读回、并发写入不损坏、损坏文件降级不抛异常 → 同文件「VideoTaskLedger 持久化」组 11 条：先落盘再轮询、跨重启读回、20 条并发写入不丢、坏文件降级后可继续写、prune 只清终结条目、remoteTaskId 去重

## 4. Agnes 视频适配器按异步生命周期改造

- [x] 4.1 `video_gen_adapter.dart`：新增 Agnes 专用的顶层字段读取（`_readVideoId` / `_readErrorMessage` 读顶层，`_pollUntilDone` 读顶层 status/progress/url），不复用 `SenseAudioVideoAdapter` 的嵌套读取静态方法
- [x] 4.2 同处：查询路径改为以 `GET /agnesapi?video_id=...&model_name=...` 为主（文档推荐，keyframe/reference 模式必须带 model_name），`/v1/videos/<id>` 降为兜底；新增 `_queryRoot` 处理根地址（`/agnesapi` 不在 `/v1` 下）
- [x] 4.3 同处：只读顶层 `status` / `progress`，忽略 `internal_status` / `internal_progress`
- [x] 4.4 同处：轮询循环抽出为 `_pollUntilDone`（供恢复路径复用），下载抽出为 `_downloadTo`
- [x] 4.5 同处：创建成功后先写台账再开始轮询（`VideoTaskLedger.record`，context 由 `VideoGenRequest` 新字段带入）
- [x] 4.6 同处：超时预算改为排队预算（默认 10 分钟）+ 生成预算（默认 15 分钟）两段，阶段由 `queued → in_progress` 切换推断（`sawInProgress` 持久化）
- [x] 4.7 同处：两段预算耗尽而任务未完成时，台账状态置为「云端仍在处理」而非 failed；错误信息明示「积分已扣除，视频未丢失」并提供 video_id
- [x] 4.8 同处：轮询间隔由 3 秒改为 2 秒；查询失败时间隔翻倍退避至 8 秒上限，成功后恢复
- [x] 4.9 同处：错误分类——400/401/403/404 立即失败不重试并透出原因；429/5xx 退避重试；`status: failed` 时透出 `error.message`。`_readErrorMessage` 读顶层 `error.message` 对象；查询路径 404 立即抛错并提示「确认保存的是 video_id 而非 task_id」；429/400-参数丢弃沿用 `_post` 既有指数退避；查询失败时间隔翻倍至 8s 上限
- [x] 4.10 同处：`agnes-video-2.5-flash` 请求体 size 固定 `"720P"`（`_sizeTier`），不提交 videos 参考；`agnes-video-2.5` 按能力声明传 size 档位
- [x] 4.11 同处：下载前校验 URL 非空，下载后校验文件大小 ≥1024 字节，不把临时地址当持久产物
- [x] 4.12 `VideoGenRequest` 新增 seriesId / episodeId / segmentId / label 四个可选台账上下文字段；`studio_generation_tasks.dart` 的片段级与分镜级调用点均已传入

## 5. 设置项与恢复入口

- [x] 5.1 新增设置项：`SettingsStore.videoQueueBudget` / `videoGenerateBudget`（默认 10 / 15 分钟）与对应 setter，持久化到 `app.json`
- [x] 5.2 新增 `video_task_recovery.dart` 并接线到 `studio_shell.dart` 的 `_bootstrap`：启动时扫描台账，对 polling / cloudProcessing 状态的任务重建轮询；`_active` 集合保证同一任务不会被认领两次
- [x] 5.3 恢复取回后走原写回路径（`manager.saveEpisode` 更新片段/分镜状态与产物路径），与 `SegmentVideoGenTask` 共用同一条写回逻辑
- [x] 5.4 队列面板展示：`storyboard_board.dart` 的 `_QueueDrawer` 新增「云端视频任务」区——阶段（排队中/生成中，取顶层 lastRemoteStatus）、已等待时长、云端进度百分比、video_id 一键复制；区级横幅与放弃确认弹窗双双明示「本地放弃不会停止云端计费」

## 6. 验证

- [x] 6.1 单元测试：台账持久化与恢复、状态机唯一活跃轮询者 → 见 3.6 的 11 条；两段预算的阶段切换由 `sawInProgress` 持久化字段承载（`backdateForTesting` 辅助验证跨重启保留），轮询循环本身依赖真实时钟，未做时间注入测试
- [x] 6.2 单元测试：Agnes 响应解析 → 改写了 `test/senseaudio_video_adapter_test.dart` 的三条 Agnes 用例，假后端现在按文档形态返回顶层 `status`/`progress`/`url` + `internal_status: pending`/`internal_progress: 0`，并断言查询 URL 用 video_id 且带 model_name
- [x] 6.3 单元测试：flash 型号请求体含 `size: "720P"` → 同上三条用例已断言 `capturedPayload['size'] == '720P'`；`test/agnes_studio_pipeline_test.dart` 的请求体用例同步改为断言 size 存在且为 720P（原断言是「不得包含 size」，与文档相反）
- [ ] 6.4 实机：用一个真实 Agnes 任务走完「创建 → 杀掉应用 → 重启 → 自动取回」全流程
- [ ] 6.5 实机：确认重启后 Agnes 控制台的创建请求计数没有增加（未产生第二次计费）
- [ ] 6.6 实机：目视「AI 供应商」快速填充里的 Agnes chip 点出来是真实地址与真实模型
- [x] 6.7 运行 `flutter test` 与 `flutter analyze`，确认无回归 → 全量 `flutter test` 通过；`flutter analyze` 改动前后基线对比零新增告警（241 → 209，差额全是工作区既有问题的修复）
- [x] 6.8 部署：`scripts/deploy_local.sh`
