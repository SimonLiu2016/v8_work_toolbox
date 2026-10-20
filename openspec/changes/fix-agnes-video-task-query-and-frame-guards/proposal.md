## Why

`agnes-provider-preset-and-async-video-lifecycle` 按 Agnes 官方文档实现了异步视频任务生命周期，但用真实 API Key 实测后发现**文档与实现有四处分歧，其中三处是直接的积分损失路径**：

1. **限流响应伪装成成功**：密集轮询（1 秒间隔）下约 25% 概率触发限流，且 Agnes 返回的是 **HTTP 200 + `{"error":{"code":429,...}}`**，不是 HTTP 429 状态码。我们的解析只判状态码，于是把错误体当正常响应读——`status` 读不到、`progress` 读不到，UI 显示"未知进度"并继续空转。
2. **兜底查询路径读不出视频地址**：主路径 `/agnesapi` 的 `url` 在响应顶层（我们读对了），但兜底路径 `/v1/videos/<id>` 的 `url` 藏在 `metadata.url` 里。两条路共用一套顶层读取，一旦走到兜底就读到空 `url`，然后**轮询到预算耗尽**——钱花了、视频在云端、本地判失败。
3. **`pending` 状态未纳入阶段判定**：文档说状态是 `queued / in_progress / completed / failed`，实测还有第五态 `pending`（出现在 `started_at` 之前、`progress=0`）。两段预算的排队→生成切换只认 `in_progress`，`pending` 被算进排队段。而响应里明明有权威信号 `started_at` 字段，我们没用。
4. **小尺寸首帧被拒且报错难懂**：Agnes 要求首帧边长 256–5760 像素。我们的降采样只压缩大图、不放过小图，一个小于 256px 的关键帧会被拒，错误信息指向 `first_frame` 参数——用户完全看不出是自己的图太小。

另有一项**用户可观测性缺口**：用户在 Agnes 控制台只能看到积分扣减，没有任何地方能回看已生成的任务与产物。而实测证明云端 URL 在任务完成后长期有效（10 分钟前的任务仍可下载，`expires_at` 为 null），所以"找回视频"在技术上是可行的——只是我们没给用户入口。

## What Changes

- **识别伪装成成功的限流响应**：查询响应先检查 `error` 字段再解析业务字段。命中限流时按瞬时故障退避，不当作"进度未知"静默继续。
- **兜底路径按自己的形态解析**：`/v1/videos/<id>` 的 `url` 从 `metadata.url` 读；两条路径各自解析，不再共用一套顶层读取。若兜底路径也取不到地址，明确报错而不是空转。
- **阶段判定改用 `started_at`**：以响应中 `started_at` 是否非空作为"排队→生成"的切换信号，不再依赖状态字符串匹配。状态取值域（含实测发现的 `pending`）在代码注释中记全。
- **首帧尺寸守卫**：首帧边长小于 256px 时明确拒绝并说明原因（"关键帧尺寸过小"），而不是把供应商的参数校验错误透给用户。
- **已终结任务可回看与取回**：任务面板的云端区展示已完成的条目（不再只显示 active），提供重新下载入口；用户可凭 `video_id` 在任何时候取回仍在云端的产物。
- **台账不主动删终结条目中的已完成项**：调整清理策略——`completed` 条目保留远长于 `failed`/`abandoned`，因为它的云端 URL 仍有效、仍有取回价值。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `async-video-task-ledger`: 查询响应须先甄别错误体再解析；阶段判定以供应商的结构化信号为准而非状态字符串；已完成任务在本地可回看、可重新取回，清理策略按其云端可取回性区别对待。
- `ai-video-studio/shot-production`: Agnes 视频生成的查询解析、阶段判定与首帧尺寸守卫按实测协议形态修正。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`_queryTask` 增加错误体甄别与兜底路径的 `metadata.url` 解析；`_pollUntilDone` 的阶段判定改用 `started_at`；`_prepareKeyframeDataUri` 增加首帧尺寸下限守卫。
- `lib/tools/ai_video_studio/services/video_task_ledger.dart`：`prune` 对 `completed` 与 `failed`/`abandoned` 用不同保留窗口。
- `lib/tools/ai_video_studio/services/video_task_recovery.dart`：新增"重新下载已完成任务"的入口。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`：云端任务区展示已完成条目并提供取回按钮。

**测试**
- 新增/改写 `test/tools/ai_video_studio/` 下用例：HTTP 200 的限流体被识别并退避；兜底路径从 `metadata.url` 取地址；`started_at` 驱动的阶段切换；小首帧被明确拒绝。
- 需同步 `test/senseaudio_video_adapter_test.dart` 与 `test/agnes_studio_pipeline_test.dart` 中按旧形态编写的假后端。

**无配置与数据迁移**：台账文件结构不变（仅清理策略调整），既有条目继续有效。
