## Why

在真实会议面板里改一个说话人的音色，会立刻触发该说话人全部轮次的重新合成：实测一场 115 轮 / 8 个说话人的会议，「说话人 3」有 53 轮（约 40 个续句组），意味着**一次下拉操作 = 40 次 TTS 调用**，顺的话 1-3 分钟，端点卡住时单次超时 90 秒、重试 2 次，可能长达数十分钟。

期间的表现是三连坏：

- 全页面按钮变灰（`_busy` 是全局单标志），且没有任何进度提示——用户以为软件卡死，只能重启
- 下拉框不回填（`_speakers` 要等合成结束才刷新），看着像"没生效"
- 更糟的是 `_resynthesizeSlot` **先删除该槽位的音频、再合成**：中途失败或退出，那个说话人的话会变成静音占位

同一条路径还被「合并说话人」与「标记为我是我」复用，三个操作共担同一风险。

根因是把**设定（瞬时、声明式）**和**烘焙（分钟级、带副作用的执行）**焊成了一个同步动作。

## What Changes

- **改设定立即生效，不触发合成**：音色、合并、标记「我」只写覆盖层并刷新展示，界面立刻反映出新值。
- **音频与设定的不一致变成可见状态**：合成状态按组记录实际使用的音色；设定的音色与记录不同时，该组标记为「待更新」，面板显示待更新组数。
- **重新合成改为显式动作**：用户点「重新合成待更新部分」才开始烘，带进度与取消。
- **重新合成失败不再破坏旧音频**：先合成到临时文件，成功才替换；失败保留原音频并把该组标记为待更新。
- **忙碌状态按操作分域**：改设定不再禁用「更新素材」「生成音频」「导入逐字稿」；长任务（生成音频、重新合成）各自独立并显示进度，且可取消。

**BREAKING**：无。合成状态文件新增按组记录的音色字段，旧数据缺失时视为"未知"，首次重新合成后补齐。

### 不做的事（明确的非目标）

- 不改 TTS 端点本身的重试/超时策略（90 秒 + 2 次重试沿用）
- 不做后台任务队列（应用退出后不续跑）
- 不改续句合并、整篇拼接、回答层的既有规则
- 不做"改音色后自动预听片段"（先听一段再决定）——留作后续

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `real-meeting-transcript`: 说话人设定与烘焙解耦（设定立即生效、音频标记待更新）；新增重建的可取消与失败不破坏旧音频；新增「音频与设定一致性」的可见状态

## Impact

**改动文件**

- `lib/tools/it_meeting_listening/models/real_meeting_models.dart` — `TurnGroupAudio` 增加 `voiceId`（该组实际合成用的音色）
- `lib/tools/it_meeting_listening/services/real_meeting_service.dart` — `setSpeakerVoice` / `mergeSpeakers` / `unmergeSpeaker` / `markSlotAsMe` 不再触发合成；新增 `pendingGroups(meeting)` 与 `rebakeGroups(meeting, indices, {onProgress, shouldCancel})`
- `lib/tools/it_meeting_listening/services/real_meeting_baker.dart` — 支持"只重合成指定组"；合成到临时文件、成功后替换；`shouldCancel` 回调
- `lib/tools/it_meeting_listening/ui/real_meeting_panel.dart` — 显示待更新组数与「重新合成」入口；下拉框改为乐观更新
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — `_busy` 拆分为 `_importing` / `_baking` / `_rebaking`；长任务进度与取消

**测试**

- 改音色：覆盖层写入 + 下拉回填 + **TTS 调用为 0**
- 待更新识别：改音色后 `pendingGroups` 返回该说话人的组；重新合成后归零
- 重新合成失败：旧音频文件仍在，组标记为待更新
- 取消：中途取消后已完成组保留、未完成组仍为待更新
- 忙碌分域：合成进行中仍能改设定、仍能打开导入

**归档顺序**

本 change 是第四个叠加在 `real-meeting-transcript` 上的修改，归档顺序必须是：

```
add-real-meeting-import
  → fix-transcript-format-tolerance
    → fix-real-meeting-audio-and-naming
      → decouple-speaker-settings-from-baking
```
