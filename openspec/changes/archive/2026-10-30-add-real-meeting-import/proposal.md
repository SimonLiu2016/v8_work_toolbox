## Why

听力练习工具现在的素材有两类：站点公开的 1-3 分钟短对话（内容与用户自己无关），以及用户材料生成的模拟会议（内容是模型演的）。用户手上还有第三类、也是最贴身的一类——**真实召开过的会议的逐字稿**（会议记录系统产出，含说话人槽位与时间戳，样例为 20 分 6 秒 / 152 轮 / 检出 6 个说话人）。这类文稿目前进不来：不能按说话人听、不能统计「这场会里反复出现的词是什么」、也不能把「会上被问到的问题」单独拎出来预演该怎么答。

真实会议既是用户实际要听懂的场景（口音、语速、术语都是自己领域的），也是唯一能回答「我当时该怎么答」的素材来源。

## What Changes

- **新增真实会议逐字稿导入**：支持导入会议记录系统产出的 MD 逐字稿（`发言人 N HH:MM:SS` + 正文的固定形态），解析出说话人槽位、时间戳与逐轮文本。首次导入的样例实测：分隔符是 NBSP（`\xa0`）而非普通空格、152 轮中 59 轮（39%）是跨说话人断句。
- **新增说话人设定**：每个「发言人 N」可改显示名、可指定音色；改名作为**覆盖层**持久化，不修改原始文稿。系统 SHALL 不自动推断"两个槽位其实是同一个人"。
- **新增续句合并后逐轮合成**：展示层与索引层保留原始轮次，**合成层**把「首字母小写且上一轮无句末标点」的轮次并进上一轮，用上一轮音色念完整组——避免在半句话中间换声音。
- **新增「我的身份」全局设定**：跨所有真实会议恒等的一组配置（显示名 + 音色），用于第 5 条的插入回答；排练会议的 `Simon` 与之共用音色，使两个功能里的"我"是同一个人。可选地把某个说话人槽位标记为"我"。
- **新增跨会议全局词汇表**：提取所有已导入真实会议的英文单词与累计出现次数；停用词默认过滤，只出现一次且在词典中不存在的词折叠进「疑似转写噪声」分组；同一篇重复导入按会议标识**覆盖不累加**。
- **新增单词反查**：任意单词可查出它出现在哪些会议的哪个说话人的哪一句、以及该句在音频中的时间点，点击直达该场会议的那一轮。
- **新增选段回答并插入**：选中某说话人的某一轮（通常是提问）→ 结合会议主题与上下文让 AI 给出英文回答，或由用户写中文后译成英文（中文原文并存供对照）→ 合成该轮语音 → 插入到该轮之后 → 重建整篇音频。插入的回答标注为「我的回答」，可重新生成、可编辑、可删除。
- **修改片段时长约束的适用范围**：真实会议是**整场**素材，不受现有「1-3 分钟、单文件不得超 5 分钟」约束；该约束继续适用于站点导入的公开素材。

**BREAKING**：无。素材库新增第三类内容（`sourceId: 'real-meeting'`），既有素材与 `Clip` 数据结构不变。

### 不做的事（明确的非目标）

- **不做 LLM 修稿**：逐字稿里的 ASR 错字与错误断句**不修**，只做机械清洗（续句合并、破折号、空白）。修稿会污染词汇统计，使词频反映"模型想写的词"而不是"会里真说的词"
- 不做原始录音对齐（用户侧没有录音，音频一律由 TTS 合成）
- 不做说话人自动聚类/合并（谁和谁是同一人由用户指定）
- 不做多篇会议合并为一场
- 不做影子跟读打分与录音对比
- 不做会议内容的云端同步或分享（纯本地）

## Capabilities

### New Capabilities

- `real-meeting-transcript`: 真实会议逐字稿的完整契约——逐字稿导入与解析（说话人槽位、时间戳、跨会断句形态）、说话人槽位改名与音色、续句合并后的逐轮合成与整篇重建、选段 AI 建议回答与中译英插入、我的身份全局设定、已插入回答的编辑与撤销
- `meeting-corpus-vocabulary`: 跨会议的全局词汇表——词频提取与累计口径（停用词、噪声折叠、重复导入去重）、单词到会议/说话人/句子/时间点的反查

### Modified Capabilities

- `it-meeting-listening-tool`: 片段时长上限的适用范围收窄为站点导入素材（真实会议是整场）；精听面板支持按轮定位、显示说话人名、标注「我的回答」；烘焙管线支持长会议的续跑与失败轮可见性

## Impact

**新增文件**

- `lib/tools/it_meeting_listening/models/real_meeting_models.dart` — 会议、说话人槽位、说话人设定、插入回答、我的身份的数据模型
- `lib/tools/it_meeting_listening/services/transcript_parser.dart` — 逐字稿解析（`发言人 N HH:MM:SS` 形态、NBSP 归一化）
- `lib/tools/it_meeting_listening/services/continuation_merger.dart` — 续句分组（合成层）
- `lib/tools/it_meeting_listening/services/real_meeting_baker.dart` — 续句组合成、逐轮音频持久落盘、整篇 concat 与时间戳重算
- `lib/tools/it_meeting_listening/services/meeting_vocabulary_index.dart` — 全局词频与倒排索引
- `lib/tools/it_meeting_listening/services/answer_generator.dart` — 选段问答 AI 生成与中译英
- `lib/tools/it_meeting_listening/services/real_meeting_store.dart` — 会议、说话人覆盖层、回答层的持久化
- `lib/tools/it_meeting_listening/ui/real_meeting_import_panel.dart` — 导入与说话人设定
- `lib/tools/it_meeting_listening/ui/real_meeting_practice_page.dart` — 逐字稿练习与选段回答
- `lib/tools/it_meeting_listening/ui/vocabulary_browser_page.dart` — 全局词汇表与反查

**改动文件**

- `lib/tools/it_meeting_listening/models/listening_models.dart` — `MeetingScene` 增加 `realMeeting`；`ClipSource` 的 `sourceId` 增加 `real-meeting`
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — 第三类内容的入口与类型筛选；精听面板按轮定位
- `lib/tools/it_meeting_listening/services/listening_player_controller.dart` — 整篇长音频的按轮 seek（已有 `_seekToTurn`，需覆盖长会）
- `lib/services/app_paths.dart` — 真实会议目录、逐轮音频目录、词汇索引文件、我的身份配置文件
- `lib/shell/settings_dialog.dart` 或「我的身份」落点 — 全局设定入口

**存储布局**

```
real_meetings/
  meetings/<meetingId>.json      原始文稿 + 说话人槽位（不改写）
  settings/<meetingId>.json      说话人改名/音色覆盖层（可删，删了回落到槽位默认）
  answers/<meetingId>.json       插入的回答层（锚点轮、中文原文、英文、音频路径）
  turns/<meetingId>/t<i>.mp3     逐轮音频（持久，不进缓存目录）
  audio/<meetingId>.mp3          整篇音频（由逐轮音频 concat 重建）
vocabulary_index.json            跨会议词频与倒排索引
my_identity.json                 我的身份（显示名 + 音色）
```

**关键实现约束**

- 逐轮音频 MUST 落在持久目录：现有排练会议把 `t{i}.mp3` 写在 `itMeetingListeningCacheDir`，而界面有「清理缓存」会调用 `clearTurnCache`。真实会议若照抄，清一次缓存后插入回答就退化成整篇重烘
- 插入回答只合成新的那一段，整篇音频靠**重新 concat 逐轮文件**重建，不重跑 TTS
- 样例实测规模：20 分钟 / 152 轮 → 约 3-6 分钟合成；60 分钟会议约 450 轮 → 约 10 分钟。烘焙必须可中断续跑，失败轮在界面上可见

**复用既有能力**

- `RehearsalBaker` 的合成防线（空音频重试、451 降级、402 fast-fail、900 字切分）与时间戳回填逻辑
- `Clip` / `SpeakerTurn` / `ClipIndex` / `ClipLibrary.saveIndex` 的落盘与索引形态
- `TermHighlighter` 的词边界分词、`ListeningTermCollector` 的收藏到生词本
- `RehearsalTextGenerator`（LLM 注入抽象）、`sanitizeForSynthesis`（破折号清洗）
- 播放器、全局热键、迷你窗、断点记忆、变速（不改）

**外部依赖**：无新增 pub 包；依赖既有 TTS 槽位与 text 槽位（AI 能力配置）
