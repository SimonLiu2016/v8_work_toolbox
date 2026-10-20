## Why

两件事，同一个根因：**我们对 Agnes 的集成只做了"能调通"，没有匹配它真实的协议与异步任务生命周期**。

其一，「添加 AI 供应商」里的快速填充 chip 写着「Agnes / 中转站 (视/图多模态)」，填进去的却是中转站时代的配置——`http://119.29.249.154:3356` 这个 IP 地址、`deepseek-chat, gpt-4o-mini` 这类与 Agnes 无关的文本模型。Agnes 中国站的真实 Base URL 是 `https://api.agnes-ai.cn/v1`，模型是 agnes-2.5/3.0 系列文本、agnes-image 系列图像、agnes-video-2.5 系列视频。chip 名不副实，填进去的配置还要用户手工纠正。

其二，用户实际在 AI 视频工坊里**付了钱却没拿到视频**：Agnes Video 是异步任务（创建 → 排队 → 生成 → 查询），5 分钟视频排队加生成完全可能超过 5 分钟；我们的适配器 5 分钟硬超时后抛错，而云端任务仍在继续，积分已扣，视频却永久丢失。用户在任务状态还是"处理中"时就看到报错，且**没有任何地方记下 video_id**——想手工去查都查不到。

## What Changes

### 1. Agnes 供应商预设改为真实配置

- 「Agnes / 中转站 (视/图多模态)」chip 更名为 **「Agnes」**，副标题去掉"中转站"。
- 预填内容改为针对 Agnes 中国站：Base URL `https://api.agnes-ai.cn/v1`；文本模型 `agnes-2.5-flash, agnes-2.5-pro, agnes-3.0-flash, agnes-3.0-pro`；图像模型 `agnes-image-2.0-flash, agnes-image-2.1-flash, agnes-image-2.5-flash`；视频模型 `agnes-video-2.5, agnes-video-2.5-flash`。
- 移除中转站 IP 与无关模型。协议仍为 `AiProtocolType.agnes`（文本链路本就是 OpenAI 兼容，无需改动）。
- 预填逻辑保持现有守卫（仅当 URL 为空或指向 openai.com 时才覆盖），不强行改写用户已填的地址。

### 2. 视频生成按 Agnes 异步任务生命周期重做

- **video_id 持久化**：创建任务成功后，立即把 `video_id`/`task_id`、模型、关联的集/片段/分镜、创建时间写入本地任务台账（`AppPaths` 下的 JSON），**先落盘再开始轮询**。进程被杀、应用重启后台账仍在。
- **轮询匹配 Agnes 协议**：改用 `GET /agnesapi?video_id=<id>&model_name=<model>` 作为主查询路径（文档明确：keyframe/reference 模式必须带 model_name，纯 video_id 只适用 text 模式）；`status` 取 `queued`/`in_progress`/`completed`/`failed`，`progress` 取 0–100 整数，完成后从**顶层 `url`** 取视频地址；忽略 `internal_status`/`internal_progress`。
- **超时改为按视频时长与排队分离计算**：单次轮询总预算从固定 5 分钟改为「排队预算 + 生成预算」两段，默认排队 10 分钟、生成 15 分钟，均可在设置中调整。轮询间隔从 3 秒改为文档建议的 1–2 秒，并对 429 做指数退避。
- **超时不等于放弃**：达到预算上限时，任务状态改为「云端仍在处理」而非失败——台账保留 `video_id`，用户可稍后一键"继续等待/取回"，也可复制 video_id 去控制台自查。**不再出现"积分扣了、视频丢了、线索也断了"**。
- **重启恢复**：应用启动时扫描台账，把处于「云端处理中」且未取回的任务重新挂起轮询，取回后写回原片段/分镜产物路径。
- **错误分类**：HTTP 4xx（参数/权限/视频 ID 不存在）立即失败并明确提示，不重试；429/5xx 走既有指数退避重试；`status: failed` 时把 `error.message` 透出。
- 查询响应的 `url` 是**带时效的临时地址**，取回后立即下载落盘，不长期引用。

### 3. Agnes 全模型能力声明补齐

`MediaCapabilityDefaults` 与 `MediaModelCapability.forModel` 当前只认 `agnes-video-2.5-flash` 和 `agnes-image-2.5-flash`，且把图像与视频声明混为一项。补齐：

- 视频 `agnes-video-2.5`：720P/1080P/1K/2K 四档、seconds 字符串 "4"–"12"、支持首尾帧、reference 模式最多 8 张图（前 5 张免费）。
- 视频 `agnes-video-2.5-flash`：**size 固定 "720P"**、不支持 videos 参考、images 最多 5 张。
- 图像 `agnes-image-2.0-flash` / `2.1-flash` / `2.5-flash`：size 1K/2K/3K/4K + ratio（9:16 时 2K = 1472x2624），三者参数一致。
- 拆分图像与视频为独立声明，修正"图像模型命中视频能力"的现状。

## Capabilities

### New Capabilities

- `async-video-task-ledger`: 云端视频异步任务的台账——创建即持久化、跨重启恢复、超时不放弃、video_id 可追溯，使用户在长任务与排队场景下不丢已付费的产物。

### Modified Capabilities

- `ai-video-studio/shot-production`: Agnes 视频生成的轮询协议、超时预算与失败语义按异步任务生命周期改写；`agnes-image-2.5-flash` 图像能力声明从视频声明中剥离。
- `ai-configuration`: 供应商快速填充预设的准确性与命名——预填值必须是该供应商的真实 Base URL 与真实模型 ID。
- `media-model-capability-matrix`: Agnes 各型号的能力声明补齐并按型号分档，未知型号走保守默认并显示「未经确认」。

## Impact

**代码**
- `lib/shell/ai_config_page.dart`（约 1294 行）：Agnes chip 更名与预填值替换。
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`AgnesVideoAdapter` 的查询路径、超时策略、错误分类、video_id 落盘。
- 新增 `lib/tools/ai_video_studio/services/video_task_ledger.dart`（或同等位置）：任务台账存储与恢复。
- `lib/services/media_capability.dart`：Agnes 视频/图像能力声明补齐与拆分。
- `lib/services/app_paths.dart`：台账存储目录。

**配置与数据**
- 新增设置项：排队预算、生成预算（默认 10/15 分钟）。
- 新增本地台账文件；不影响既有配置键，无需迁移。

**测试**
- `test/tools/artex_engine/` 无关。需为台账的持久化/恢复/超时不放弃补测试；`AiProtocolType.agnes` 的文本链路已有覆盖，协议本身不改。

**部署**
- 改动集中在 AI 视频工坊与 AI 配置页，`flutter build macos --release` + `scripts/deploy_local.sh` 常规部署。
