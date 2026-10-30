## Context

动机见 proposal.md，需求见 `specs/it-meeting-listening-tool/spec.md`。

现状：

- `ListeningProgressStore` 以 `sceneId` 为键存 `{clipId, offsetMs, updatedAt}`，单文件 JSON。
- 唯一写入点在页面 `_playClip` 里：`save(clip.scene.id, clip.id, 0)`——开始播放时写、偏移恒为 0。
- 播放由 `ListeningPlayerController`（`ChangeNotifier`，持有 position、队列、`play/pause/seek/next/previous`）承担，`ListeningHost` 单例持有它并桥接迷你窗命令（`handleMiniCommand`）与热键。三条控制路径最终都经过 controller。
- 排练与真实会议的 `Clip.scene` 分别是 `MeetingScene.rehearsal` / `MeetingScene.realMeeting`，多场共享同一个 sceneId——按场景存会互相覆盖。

## Goals / Non-Goals

**Goals:**
- 写入逻辑集中在共享播放层，一处实现、三条控制路径共享。
- 按内容记位置，同时保留"场景内最后片段"与全局 lastPlayed。
- 写入廉价：周期写入不应造成可感知的 I/O 抖动。

**Non-Goals:**
- 不做跨设备同步。
- 不做"已听完"列表或收听统计（只提供进度数据供 UI 显示百分比）。
- 不改页面布局（启动恢复的界面呈现属于 `redesign-listening-practice-layout`）。

## Decisions

### D1. 数据结构（单文件，版本化）

```json
{
  "version": 2,
  "items":  { "<clipId>": { "offsetMs": 760000, "durationMs": 2890000, "updatedAt": "..." } },
  "scenes": { "<sceneId>": { "clipId": "...", "updatedAt": "..." } },
  "lastPlayed": { "clipId": "...", "updatedAt": "..." }
}
```

- 键统一用 `Clip.id`：公开片段 id、`rehearsal_<material>`、真实会议 id 都已全局唯一，无需新增"内容类型"维度。
- `durationMs` 冗余存储，便于 UI 不加载音频即可算已听百分比。
- `scenes` 只记片段 id（偏移从 `items` 取），避免两处偏移不一致。
- **替代方案**：每内容一个文件。否决：内容数可达数百，单文件小而读写简单；写入用"临时文件 + rename"原子替换。

### D2. 旧格式迁移

读取时若无 `version` 字段视为 v1（以 sceneId 为键的旧表）：转换为 `scenes[sceneId] = {clipId}`，`items[clipId] = {offsetMs}`（旧值恒为 0），`lastPlayed` 取 `updatedAt` 最新的一条。下一次写入即落为 v2。损坏文件按空表处理（沿用现有容错）。

### D3. 写入集中在 `ListeningPlayerController`

新增 `ResumeRecorder`（注入到 controller，便于测试替身）：

| 触发 | 动作 |
|---|---|
| 播放中每 5 秒（以 position 流节流） | 内存更新 + 防抖落盘 |
| pause / stop / seek / 切换 clip（play 新内容前） | 立即落盘旧内容的位置 |
| 播放完成 | 记为已听完（offset 置 0） |
| 迷你窗关闭、页面 dispose、应用退出（`AppLifecycleState.detached` / 窗口关闭钩子） | 立即落盘 |

- 内存中维护完整表，落盘串行化（单个 pending future），避免并发写导致的覆盖。
- 页面中的 `save(..., 0)` 删除。

### D4. 已听完判定

`remaining < 5s || offset/duration >= 0.98` ⇒ 写入 `offsetMs = 0` 并在 `items` 中保留 `durationMs`；UI 显示进度时，已听完显示为 100% 需要额外标记——在 item 上增加 `completedAt`（可选），offset 置 0 时同时写入，重新开始播放后清除。

### D5. 恢复 API

- `ResumeRecorder.offsetFor(clipId)`：`play(clip)` 时若未显式指定位置，载入后 seek 到该偏移。
- `ResumeRecorder.lastPlayed`：供页面启动时读取；本变更中，现有页面在启动时用它选中场景与片段并载入（暂停态），为新布局提供同一能力。
- `ResumeRecorder.sceneLastClip(sceneId)`：场景连续播放从该片段继续。

## Risks / Trade-offs

- [周期写入的 I/O] → 5 秒一次、仅在播放中、单个小 JSON，原子替换开销可忽略。
- [应用被强杀时退出钩子不触发] → 周期写入兜底，最多丢 5 秒（与需求一致）。
- [seek 到记录位置时音频文件已被重新合成、时长变化] → 偏移超过新时长时从头播放。
- [迷你窗是独立窗口进程内通道] → 迷你窗只发命令，播放仍在主 controller，记录不需跨窗口。

## Migration Plan

- 首次启动新版本时自动读取 v1 并在下一次写入时升级为 v2；无需用户操作。
- 回滚：旧版本读取 v2 文件会因结构不符而当作空表（现有容错），仅丢失断点、不报错。
