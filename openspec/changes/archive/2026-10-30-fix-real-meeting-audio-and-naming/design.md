## Context

见 `proposal.md - Why`。这里只记录决定修法的实测事实。

**现状证据**（本机，导入后状态）：

```
real_meetings/
  turns/rm_91ac…/   115 个 g*.mp3（60MB）   ← 逐组合成全部成功
  audio/rm_91ac….json（17.7K）              ← 合成状态已写
  audio/rm_91ac….mp3                        ← 不存在
```

`ffmpeg 8.0.1` 位于 `/usr/local/bin`，可用。**不是环境问题**。

**自锁链**：

```
isAvailable => _ffmpegPath != null      （audio_toolkit.dart:35）
        │  该字段只在 resolveFfmpeg() 内赋值
        ▼
rebuildAudio 里 if (_audio.isAvailable) { concat }   （real_meeting_baker.dart:413）
        │  启动后恒为 false → 永不进入
        ▼
_ffmpegPath 始终 null ──► 永远跳过 concat
```

唯一的 `resolveFfmpeg()` 调用点在 `concat()` 与 `writeSilence()` 内部，而 `writeSilence` 只在合成失败时执行——**全部成功的那条路径永远碰不到它**。

## Goals / Non-Goals

**Goals:**

- 让"索引里的素材"与"磁盘上的音频"保持一致，不留播不了的条目
- 已经坏在盘上的会议不重新导入就能自愈
- 改名与说话人改名同一套约定：覆盖层、可清除、不碰原稿

**Non-Goals:**

- 不做音频完整性巡检（不主动扫描所有素材的音频是否存在）
- 不改场景分组名称
- 不解决 ffmpeg 未安装的场景，只保证它**大声失败**而不是静默跳过

## Decisions

### D1：删掉 `AudioToolkit.isAvailable`，而不是让它"稍微聪明一点"

**备选 A**：把 `isAvailable` 改成异步并内部 `resolveFfmpeg()`。否决——它仍然是一个"能力查询"，调用点仍然可以选择性忽略它；这次的问题不是判断写错了，而是**这类判断本身就没有价值**：拼接失败时 `concat` 已经会抛 `StateError('未检测到 ffmpeg…')`，调用点真正需要的是"失败就失败"，而不是"事先问一句然后决定要不要做"。

**备选 B**：保留属性但每次调用都刷新。否决——把惰性解析藏进 getter 会让调用点更难预判，且依然挡不住下一次有人写 `if (isAvailable)`。

**做法**：接口只保留 `concat / probeDurationMs / writeSilence`，三者在缺 ffmpeg 时各自抛错或（对 `writeSilence`）按既有约定退化为空文件。调用点去掉判断。

### D2：发布前校验文件存在，缺失则以占位形态入库

`rebuildAudio` 在返回 `Clip` 之前检查整篇音频文件是否真的存在：

```
文件存在  → Clip.audioPath = 'real_meetings/audio/<id>.mp3'
文件缺失  → Clip.audioPath = ''            （占位）
```

占位形态是素材库既有的概念（`Clip.isPlaceholder`），公开素材在"抓取了但没烘焙"时就是这样。复用它，而不是发明一个新状态。

**为什么不能只报错**：会议数据、逐字稿、说话人设定都已经落盘，把它们从列表里彻底藏起来会让用户以为导入丢了。占位 + 「生成音频」可修，是更诚实的表达。

**代价**：场景列表里会多出几个"待生成"的会议条目。这正是公开素材一直以来的表现，不算新问题。

### D3：「生成音频」按来源分流

```
               ┌─ sourceId != real-meeting ──► ClipBaker（按片段形态）
生成音频 ──────┤
               └─ sourceId == real-meeting ──► RealMeetingService.bake（整场形态）
```

**为什么必须分流**：`_bake()` 现在会从 `Clip` 反推 `FetchedDialogue` 再交给 `ClipBaker`。真实会议若走这条路，会被按 3 分钟切成一堆碎片——把整场素材毁掉。两条管线的输入结构与产出形态本来就不同，混用不是"复用"而是"误用"。

**顺带**：分流后，盘上已损坏那一场点一次即可修复（逐组音频还在，续跑直接复用，只补拼整篇）。

**「待生成」的判定必须包含"文件不存在"**：只看 `isPlaceholder` 会漏掉历史 bug 留下的记录——它们带着音频路径、文件却不在。这类记录正是本次要修的症状，漏掉它们等于按钮仍然说"没有需要生成的素材"。

### D4：显示名走覆盖层，与说话人改名同一处

`settings/<id>.json` 增加 `displayTitle`。`RealMeetingService` 在发布素材时用 `displayTitle.isEmpty ? meeting.title : displayTitle` 作为 `Clip.title`。

**为什么不改原稿的 H1**：原稿只读是既有的硬约定（design D2 of `add-real-meeting-import`）。重新导入同一文件时原稿会被替换，标题也应随之回落——覆盖层天然满足这一点。

**备选**：新建 `overrides/<id>.json`。否决——为一个字段多开一层文件，与说话人设定的生命周期完全相同，没有独立存在的理由。

### D5：自愈不需要迁移脚本

已损坏的会议在修复后有两种触发方式：点「生成音频」（D3 分流会选中它），或在该会议面板点「重新合成」。两者都会走 `bake(resume: true)`，复用 115 个逐组音频，只补整篇拼接。

不做自动迁移：应用启动时扫描并修复所有会议会让冷启动多一次全量 IO，而这类损坏只可能来自这一版 bug。

## Risks / Trade-offs

- **ffmpeg 真缺失时整场合成失败** → 这是期望行为（大声失败优于静默跳过）。界面会显示具体原因；逐组音频仍然留着，装好 ffmpeg 后重试即可
- **占位素材混进"连续播放"队列** → 播放器遇到空 `audioPath` 时应跳过而不是报错。实现时需确认 `_playClip` 的提示与 `next()` 的行为
- **改名与重新导入的交互** → 重新导入后若文稿未变则无操作（标题保持自定义）；若文稿变了，`displayTitle` 仍保留（用户给这场会起的名字不该因为文稿更新而丢）
- **`Clip.title` 是派生值** → 改名后必须重新 `_publish` 一次，否则索引里的旧标题会继续显示。这与既有的"任何会议数据变更后重建索引"约定一致
- **归档顺序** → 这是第三个叠加在 `real-meeting-transcript` 上的 change，必须最后归档

## Migration Plan

无数据迁移。覆盖层新增键对旧文件缺省为空；已损坏会议在用户触发重建时自愈。

回滚：还原代码即可。占位素材会重新变回带路径的记录（尽管仍然播不了），不影响其它数据。
