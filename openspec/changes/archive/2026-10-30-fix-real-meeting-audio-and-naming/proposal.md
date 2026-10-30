## Why

真实会议导入后界面显示「合成完成」，但点播放提示「该素材尚未生成音频」，点「生成音频」又提示「没有待生成的素材」——素材卡在一种**既能被索引描述、又播不出声**的状态里，且没有任何入口能修。

根因是一个懒解析的同步属性：`FfmpegAudioToolkit.isAvailable` 读的是 `_ffmpegPath != null`，而该字段只在 `resolveFfmpeg()` 里赋值；`rebuildAudio` 却用它来决定要不要拼接整篇音频。启动后它恒为 `false`，于是整篇 mp3 从未被拼出来——实测本机 `turns/` 下有 115 个逐组音频（60MB）、`audio/` 下没有任何 mp3。

同时该属性还在另一处造成静默降级（多段轮次只保留第一段），以及素材名无法自定义。

## What Changes

- **删除 `AudioToolkit.isAvailable`**：拼接失败时由 `concat` 自己抛错，而不是在调用点静默跳过。这是一个"懒解析能力暴露成同步布尔"的陷阱，保留它等于保留整类 bug。
- **发布素材前校验音频文件真实存在**：文件不存在时以**占位形态**（`audioPath` 为空）进入素材库，而不是写一条播不了的记录。索引只描述实际产出。
- **「生成音频」按来源分流**：公开素材走既有 `ClipBaker`，真实会议走 `RealMeetingService.bake`。给盘上已经坏掉的会议一条自愈入口。
- **会议显示名可自定义**：在覆盖层增加 `displayTitle`，改名只影响展示与索引标题，MUST NOT 修改原稿的 H1。
- **多段轮次不再静默截断**：拼不了多段时该组标记为失败并在界面上可见，而不是悄悄只留第一段。

**BREAKING**：无。已落盘数据格式不变（覆盖层多一个可选键）；已损坏的会议无需重新导入，点一次「生成音频」或「重新合成」即可自愈。

### 不做的事（明确的非目标）

- 不改场景分组（`站会 / 故障排查 / 真实会议`）的名称——那是写死的枚举，改成动态分组是另一个量级的改动
- 不改说话人改名、合并、回答层的既有契约
- 不做 ffmpeg 的内置捆绑或自动安装（缺失时大声报错即可）
- 不做音频文件的自动巡检（只在用户触发合成/重建时校验）

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `real-meeting-transcript`: 整篇音频的产出增加"文件真实存在才发布"的约束与占位形态；新增会议显示名覆盖层；多段合成失败时该组必须可见而不是静默截断
- `it-meeting-listening-tool`: 「生成音频」按来源分流，覆盖真实会议的缺失音频重建

## Impact

**改动文件**

- `lib/tools/it_meeting_listening/services/audio_toolkit.dart` — 删除 `isAvailable` 成员
- `lib/tools/it_meeting_listening/services/real_meeting_baker.dart` — 去掉两处 `isAvailable` 门禁；`rebuildAudio` 校验文件并在缺失时产出占位素材；多段拼接失败标记该组失败
- `lib/tools/it_meeting_listening/services/real_meeting_service.dart` — `_publish` 只在音频存在时写 `audioPath`；新增 `renameMeeting`
- `lib/tools/it_meeting_listening/models/real_meeting_models.dart` — 覆盖层增加 `displayTitle`
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — `_bake()` 按 `sourceId` 分流；会议名下增加改名入口
- `lib/tools/it_meeting_listening/ui/real_meeting_panel.dart` — 会议 chip 上提供「重命名」

**测试**

- `test/it_meeting_listening/real_meeting_baker_test.dart` — 假 `AudioToolkit` 改为能在"拼接失败"下行为正确；新增"无 ffmpeg 时不产出假素材"用例
- 新增：音频文件缺失 → 占位 → 「生成音频」修复的端到端用例

**归档顺序（重要）**

`real-meeting-transcript` 的能力基线由 `add-real-meeting-import` 归档时创建，且 `fix-transcript-format-tolerance` 已在该基线之上叠加了修改。归档顺序必须是：

```
add-real-meeting-import  →  fix-transcript-format-tolerance  →  fix-real-meeting-audio-and-naming
```
