## Context

在短视频工坊中生成大段视频或分镜视频时，底层由 `AgnesVideoAdapter.generateVideo` 组装 HTTP Body 并向 Agnes API (`POST /v1/videos`) 发起请求。任务创建成功后，会写入 `VideoTaskLedgerEntry` 台账。
当用户在分镜看板的任务抽屉 (`_CloudTaskTile`) 中点击「在试炼场调试」时，调用 `PlaygroundDraft.fromLedgerEntry(entry)` 生成草稿并载入 `PlaygroundPage`。

当前排查出以下三处导致与真实请求不一致及阻碍调试的问题：
1. **字段键名不一致**：适配器写入快照使用 `aspectRatio`、`durationSeconds`、`resolution`，而 `PlaygroundDraft.fromLedgerEntry` 读取 `ratio`、`durationSec`、`sizeTier`，导致草稿画幅比例丢失（为空）、时长和尺寸档位回退至默认值。
2. **素材角色混淆**：适配器将 `inputImage`、`lastFrameImage` 和 `referenceImages` 全部合并到了单一的 `referencePaths` 数组中。导入试炼场时全部打上 `PlaygroundMediaRole.reference`。当任务为 `keyframe` 模式时，触发试炼场的模式互斥拦截（“首尾帧模式下不可添加参考素材”），无法直接发送或复现。
3. **缺少真实脱敏 HTTP Request Body 快照与一键复制**：原实现仅展示简要的键值对概览，没有保存实际提交给 Agnes 接口的 JSON payload，且对话框中无「复制」按钮。

## Goals / Non-Goals

**Goals:**
- 实现工坊任务快照与试炼场草稿 100% 参数保真：画幅比例、分辨率档位、时长、随机种子完全对齐。
- 显式区分首帧、尾帧与普通参考图的本地路径存储，试炼场草稿精准恢复对应的 `PlaygroundMediaRole`，彻底消除模式互斥校验错误。
- 在 `VideoTaskLedgerEntry.requestSnapshot` 中持久化脱敏后的真实 HTTP Request Body JSON（base64 替换为长度与尺寸摘要），确保用户看到的请求数据与发往网络层的 100% 一致。
- 在 `PlaygroundPage` 及看板 `_CloudTaskTile` 中提供「复制完整请求 JSON」与「查看请求体」能力。

**Non-Goals:**
- 不在此阶段修改 `PromptAssembler.buildSegmentPrompt` 中的提示词生成算法（该项为下一阶段独立重构任务）。
- 不更改 Agnes 官方 API 的调用协议。

## Decisions

### 1. 扩充 `requestSnapshot` 字段结构与双向兼容

在 `AgnesVideoAdapter.generateVideo` 中：
- 同时写入：
  - `aspectRatio` 和 `ratio`: 画幅比例（如 `"9:16"`）
  - `sizeTier` 和 `resolution`: 分辨率档位（如 `"720P"`）
  - `durationSec` 和 `durationSeconds`: 持续时间（秒数整型）
  - `firstFramePath`: 首帧文件路径（可空）
  - `lastFramePath`: 尾帧文件路径（可空）
  - `referencePaths`: 纯参考图文件路径列表
  - `rawPayload`: 脱敏后的完整 HTTP JSON 请求体（保留所有字段结构，将 `data:image/...;base64,...` 替换为 `<base64: len=...>`）

在 `PlaygroundDraft.fromLedgerEntry` 中：
- `ratio`: `snapshot['ratio'] ?? snapshot['aspectRatio'] ?? ''`
- `sizeTier`: `snapshot['sizeTier'] ?? snapshot['resolution'] ?? ''`
- `durationSec`: `snapshot['durationSec'] ?? snapshot['durationSeconds'] ?? 5`
- 媒体恢复：优先读取 `firstFramePath`（赋 `PlaygroundMediaRole.firstFrame`）、`lastFramePath`（赋 `PlaygroundMediaRole.lastFrame`）和 `referencePaths`（赋 `PlaygroundMediaRole.reference`）。若为老版本快照且 `mode == 'keyframe'`，自动将前两个项分别识别为首帧和尾帧。

### 2. 真实脱敏请求 Payload 渲染与剪贴板一键导出

- 在 `PlaygroundDraft` 中新增 `rawPayload` 字段及 `formattedRawPayloadJson` getter（使用 `JsonEncoder.withIndent('  ')` 美化）。
- 在 `PlaygroundPage` 的请求体查看弹窗 (`_showRequestView`) 中：
  - 支持切换或同时展示「脱敏参数视图」与「原始 HTTP JSON 视图」。
  - 弹窗底部增加「复制 JSON」和「复制文本」按钮，点击写入系统剪贴板并弹出 Toast。
- 在 `_CloudTaskTile` 弹出的上下文操作中，新增「查看请求体 / 复制 JSON」按钮，无需进入试炼场亦可直接拷贝底层 AI 请求内容。

## Risks / Trade-offs

- [Risk] 老版本生成的历史任务台账快照不包含 `rawPayload` 或独立首尾帧路径。
  → Mitigation: `fromLedgerEntry` 内置回退与推断机制：若无 `rawPayload`，根据当前 draft 的参数实时构建一份模拟脱敏 payload；若无 `firstFramePath`，根据 `mode == 'keyframe'` 智能推断前序素材的角色。
- [Risk] 超大提示词或多图导致脱敏 JSON 渲染卡顿。
  → Mitigation: 严格对 base64 图片数据进行截断脱敏，仅保留元信息和字节长度摘要，JSON 文本控制在几 KB 内，保证弹窗和复制秒级响应。
