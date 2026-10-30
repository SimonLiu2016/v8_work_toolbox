## Context

见 proposal.md - Why。此处只记录**实测得到、且直接约束实现方式**的事实。

**已验证的可行性结论**（本机实测，2026-10-21）：

- CoderSlingo 全站 **14212 个页面、零音频**（逐页扫描 `.mp3`/`.wav`/`.ogg`/`.m4a`/`<audio>`/`<video>` 全部为 0；service worker 与全部 JS bundle 中也无 `Audio(`/`utterance`/`playbackRate`）。它提供的是**带说话人标签的 IT 会议对话文本**。
- 其听力区 18 个场景中，可解析出对话轮次的有 10 个，合计 **236 轮**。场景覆盖：站会、故障排查、Sprint 规划、架构评审、技术演讲、面试、产品演示、引导通话、客户支持。
- 站点**无音频、无需登录、`vip_type=0`**；`robots.txt` 显式 `Allow: /` 并单独放行 `ClaudeBot`/`GPTBot`；提供 `llms.txt`、`llms-full.txt`、`search-index.json`、开放数据集（CC-BY 4.0）。
- 页面结构为 Astro 静态站，`<pre class="transcript-text">` 内是纯文本对话，轮次形如 `Lena (Scrum Master): "..."`。
- **文本里的破折号会改变语义**：`Today I'll continue — but I'm blocked.` 被合成成 "but unblocked"。必须清洗。

**TTS 侧的实测约束**（应用自有 `tts` 槽位 `stepaudio-2.5-tts` @ `http://119.29.249.154:3356`）：

- 逐轮合成**零失败**（12/12 一次成功，30 轮批量烘焙 71s 完成）。
- 文本保真度以 whisper `small` 校验：术语、数字、时间戳逐字准确（`503s`、`1,200 transactions per minute`、`14:32 UTC`、`upstream payment provider`、`dependency failure`、`roll back`）。**此前观察到的"术语读错"是 whisper `tiny` 的识别误差，不是合成缺陷**——`tiny` 会把 `API spec` 听成 `API's spag`、把 `hotfix` 听成 `heart fixes`，`small` 全部正确。
- 音色 31 个，实测基频（F0 自相关）后男声 7 个、女声 24 个。**音色名不可信**：`step_boy` 实测 207Hz（女声）。
- 端点**不接受多音色单次请求**（一次请求多段 SSML 只有第一段出音），必须逐轮合成后拼接。
- `response_format` 支持 `mp3`/`wav`/`flac`/`opus`；不支持 `aac`。本应用 `OpenAiTtsEngine` 走 `mp3`。
- `speed` 参数可用（0.75/1.25 实测正常）。

**本仓库可复用的既有能力**：

- `OpenAiTtsEngine`（`lib/tools/reader/services/tts_engine.dart`）已实现槽位解析、密钥取用、429 退避重试、格式回退。
- `studio_sound_design.dart` 已实现"按角色分批合成 + 记录真实时长"的模式。
- `private_player/services/ai_subtitle_service.dart` 已实现 ffmpeg 路径探测与音频切片。
- `lookup_panel/ui/lookup_window.dart` 是透明无边框置顶浮窗的现成原型。
- `AppDelegate.swift` 已有 Carbon `RegisterEventHotKey` 的两处现成用法（⌥D/⌥S）与 `NSStatusItem` 托盘。
- `notebook/note_database.dart` 的 `VocabEntries` 表已有 `audioUrl`/`phrases`/`sourceContext` 列可承载来源信息。
- `desktop_multi_window` 支持子窗口 + `WindowController` 跨窗口调用。

**已知不在本次范围**：仓库既有 `EdgeTtsEngine` 当前对所有请求返回 400（端点与鉴权已失效），本工具不依赖它，也不修它。

## Goals / Non-Goals

**Goals:**

- 素材生产链路完全本地：抓文本 → 清洗 → 逐轮合成 → 拼接 → 落盘。烘焙完成后，播放不依赖任何网络。
- 播放控制与内容管理分离：管理在主窗口，播放在常驻小窗，两者共享同一份播放状态。
- 播放不打扰工作：常驻窗不抢焦点，全局热键在任意应用生效。
- 素材可追溯：每条素材记录来源站点、原文页面地址、许可标识与每轮音色。

**Non-Goals:**

- 不做浏览器插件形态（首版仅桌面端）。插件需要重写全部播放与存储能力，而仓库已有托盘/热键/子窗口全套。
- 不做导入用户自己的会议录音（ASR 槽位当前 404，需另找 ASR 源）。spec 中"多来源共存"只保证数据模型可扩展，不在首版实现导入。
- 不做影子跟读与发音打分。
- 不做学习时长统计、打卡、连续天数、积分。
- 不修 `EdgeTtsEngine`。
- 不做影子跟读、语法讲解、四六级等通用英语内容。

## Decisions

### D1: 素材文本取自 CoderSlingo，音频由本地 TTS 合成

**决策**：以 CoderSlingo 的听力页面文本为唯一内容来源，用应用自有 TTS 槽位合成音频。

**理由**：CoderSlingo 覆盖了需求里 8 个会议场景中的 7 个，文本带说话人标签与角色标注（`Lena (Scrum Master)`），CC-BY 许可清晰，`robots.txt` 明确允许抓取。它缺的只有音频，而音频恰好是本仓库能自给的（TTS 槽位已配置并实测可用）。

**备选与取舍**：
- *原版切片（Syntax / The Changelog / Google Tech Talk）*：音频天然真实，但下载+切片+打标签是另一条管线，且这些源多有版权顾虑、无逐句文稿。
- *可可英语*：有真实人类语音与词级时间戳，但内容是 VOA/BBC/经济学人，**没有 IT 会议**；且其 API 需逆向 MD5 签名 + AES-CBC 解密，稳定性依赖第三方实现。定位为"其它场景及日常"（用户已确认不冲突），不进本工具首版。
- *自写剧本 + TTS*：场景最精准，但文本质量与真实 IT 会议的差距大，且需人工维护；本方案里 CoderSlingo 文本是现成且更高质量的。

### D2: 逐轮合成 + ffmpeg 拼接，不做多音色单请求

**决策**：每一轮对话单独发起一次 TTS 请求得到一个音频文件，再用 ffmpeg concat 拼成片段音频。

**理由**：实测端点**一次请求内多段 SSML 只有第一段出音**（其余段返回 0 字节），单请求方案拿不到多角色对话。逐轮合成还带来三个额外好处：(a) 单轮失败可单独重试而不必整段重做；(b) 轮次边界天然成为可定位的时间戳；(c) 每轮可独立选择音色，从而实现角色固定映射。

**备选与取舍**：*ffmpeg adelay/amix 混音*可实现"插话"效果（重叠说话），但实测 mp3 输入报 `Header missing`、且混音后无法回推每轮时间戳。首版放弃插话重��，保留轮次间 0.16-0.42s 的自然停顿（实测已足够）。

### D3: 破折号清洗为逗号，且只作用于送入 TTS 的副本

**决策**：送入合成前把 `—`/`–`/`--` 替换为逗号、折叠空白、剥掉冗余引号；**原始文本单独保留**用于文稿展示。

**理由**：实测 `Today I'll continue — but I'm blocked.` 被合成成 "but unblocked"——**语义反转**，这是致命错误。替换为逗号保留了语义停顿且不改动任何单词。原始文本必须保留，否则文稿与音频会不一致，用户精听时对不上。

**备选与取舍**：*直接删除破折号*（`"Today I'll continue but I'm blocked"`）更安全但丢节奏；*保留原文*则音频必错。清洗规则只动标点，不动术语/数字/工单号——实测这些内容在 `small` 模型下逐字保留。

### D4: 音色按"角色固定"分配，映射表显式声明

**决策**：维护一张显式的"角色 → 音色"映射表，同一角色跨片段跨场景恒定用同一音色。映射依据是**实测 F0** 而非音色名字面。

**理由**：学习价值来自"听声辨人"的形成。实测 F0 显示 `step_boy` 实为 207Hz 女声、`boyinnansheng` 为 130Hz 男声——按名字猜会全错。角色固定 + 显式映射表让映射可审阅、可调整，且不依赖任何在线元数据。

**备选与取舍**：*按轮转分配*（不固定角色）会破坏听声辨人。*用 `instructions` 制造变体*实测会让模型**改写内容**（危险），故不用；需要同性别多角色时改用 `speed` 参数（0.9/1.1）做可辨识差异。

**角色集合与音色数**：一个场景通常 2-4 个说话人，7 个可信音色（3 男 4 女）足够。首版角色集：站会（Scrum Master / Backend / Frontend / QA）、故障（IC / Lead / Comms / DBA / Eng）、规划（PO / Dev Lead / Stakeholder）、支持（Agent / User）。

### D4b: 只收录"整段对话"形态的栏目

站点的听力区有两种内容形态，必须区别对待：

| 形态 | 栏目示例 | 正文 | 可用性 |
|---|---|---|---|
| 对话转写 | `standup-dialogues`、`incident-calls`、`sprint-planning`、`architecture-talks`、`customer-support-calls` | `<pre class="transcript-text">` 里的逐句对话 | ✅ 直接切出说话人轮次 |
| 单句问答 | `conference-panels/*`、`executive-briefings/*` | 一道选择题，选项里**引用**一句对话 | ❌ 只是一道词汇题 |

后者**不进素材库**（映射表里不收录，抓取只走映射表）。理由：它没有完整对话、没有说话人结构、没有音频时长——合成出来是"一句孤立的话"，不是会议。

**代价**：圆桌（Roundtable）与干系人同步（Stakeholder Sync）两个场景首版**没有素材**。站点的这两个场景恰好都是单句问答形态，无法从中提取对话。**这是内容来源的客观限制，不是实现取舍。**

### D5: 片段 = 一个 transcript block，按 3 分钟上限切分

**决策**：CoderSlingo 的每个 listening 页面含 3-5 个 transcript block，一个 block 即一条素材；超过 3 分钟的 block 在说话人轮次边界处切分为多条。

**理由**：实测 block 0 的 standup 为 38.6s、incident 为 66.1s，正好落在 1-3 分钟目标区间。切分点落在轮次边界保证不切断句子。

**备选与取舍**：*一个 block 不切*会让部分素材超 5 分钟（违反 spec 上限）；*按固定时长硬切*会切断句子。故按轮次边界贪心切分。

### D6: 素材与文稿分离落盘，同目录配对

**决策**：每个片段落盘两个文件——`<id>.mp3`（音频）与 `<id>.json`（文稿清单，含每轮文本/说话人/角色/音色/起止毫秒/来源地址/许可标识）。另有一个索引文件描述全部场景与片段。

**理由**：文稿清单是精听模式（逐句高亮、术语高亮、摘要）、术语收藏（记录来源与时间点）、以及将来"导入自己录音"（同构的 manifest）共用的数据结构。JSON 明文便于排障、便于人工修正，也便于未来做导入导出。

**备选与取舍**：*把文稿塞进 SQLite*需要给主库加表并做迁移；JSON 文件 + 索引更轻，且素材目录天然适合整目录拷贝/清理。

### D7: 播放状态集中在主进程，悬浮窗是它的视图

**决策**：音频播放、状态、进度由**主进程**持有；迷你悬浮窗是独立子窗口，通过 `desktop_multi_window` 的 `WindowController.invokeMethod` 与主进程通信，主进程把状态变更推给悬浮窗。

**理由**：`desktop_multi_window` 的子窗口是**独立 Dart isolate**。若播放逻辑放子窗口，主窗口的管理界面就拿不到真实播放状态（D3 要求的"两处状态一致"无法实现）；若播放逻辑放主窗口，悬浮窗关闭会终止播放（D5 要求的"关闭不终止"）。放在主进程 + 悬浮窗只做渲染，两个要求同时满足。

**备选与取舍**：*悬浮窗内自持播放*会牺牲状态一致性；*用事件总线跨 isolate*需要额外抽象。`WindowController` 的 `invokeMethod` / `setWindowMethodHandler` 已是现成机制。

### D8: 播放用 audioplayers，变速用其原生 playbackRate

**决策**：用既有 `audioplayers` 播放 mp3，变速走 `setPlaybackRate`（0.75/0.9/1.0/1.25）。

**理由**：`audioplayers_darwin` 在 macOS 上用 `AVPlayer`，并显式设置 `audioTimePitchAlgorithm = .timeDomain`——**变速时音高保持**，正是"慢速磨耳朵"需要的。无需 ffmpeg 预渲染变速版本，磁盘占用减半，且变速可实时切换。

**备选与取舍**：*ffmpeg `atempo` 预渲染*会保留音高但需要为每档速度生成一份文件、且切变速有延迟；*`media_kit`（mpv）*功能更强但对纯音频是重型依赖，仓库虽已有但本场景没必要。

### D9: 抓取与烘焙是显式的用户动作，不是后台自动

**决策**：抓取与烘焙由用户在管理界面显式触发（"更新素材"/"生成音频"），带进度与逐条结果，不做后台定时任务。

**理由**：烘焙要消耗外部 TTS 配额与时间（30 轮约 71s），后台自动跑会产生意外消耗；且用户需要知道素材何时可用。

**备选与取舍**：*首次启动自动烘焙*体验上更顺滑但不可控；*cron 定时更新*在常驻应用里是常见的，但这个工具的定位是"碎片间隙用"，素材更新是低频动作，显式更合适。

### D10: 场景映射表显式声明，不做名称模糊匹配

**决策**：维护一张 `站点栏目 → 内部场景` 的显式映射表，只处理列入表中的栏目。

**理由**：CoderSlingo 的栏目命名是中文的（"站会对白"/"Live Incident Bridge Calls"），靠模糊匹配会随站点改版漂移。显式表在站点改版时会**明确报错**（"页面结构已变化"），而不是静默产出错误素材。

### D11: 摘要走 LLM 槽位，在烘焙阶段生成

**决策**：用应用「AI 能力配置」的 `text` 槽位为每个片段生成一句摘要，与音频一同落盘。

**理由**：摘要要在离线播放时能按需展开，若在播放时实时生成会卡顿且依赖网络。烘焙时生成一次即可。实测该槽位已绑定可用模型。

**备选与取舍**：*用启发式从轮次里抽首句*零成本但抓不到"结论"（实测 incident 片段的结论在第 5-6 轮，不是首句）。*让 LLM 显式输出"议题 + 结论"两段式*更可控，故 prompt 里固定这两项。

## 试点结论（2026-10-21，任务组 0）

试点烘焙了 3 条素材（站会 / 故障排查 / Sprint 规划各一，共 25 轮，约 90 秒），
产物在 `/tmp/it_listening_pilot/materials/`。逐条用 whisper `small` 转写比对。

### 产出

| 场景 | 轮次 | 时长 | 大小 |
|---|---|---|---|
| 站会 Stand-up Dialogues | 8 | 49.2s | 753 KB |
| 故障排查 Incident Bridge Calls | 9 | 101.1s | 1.6 MB |
| 迭代规划 Sprint Planning | 8 | 77.2s | 1.2 MB |

25 轮**零失败**（无一次空音频、无一次重试）。

### 文本保真度：术语与数字全部正确

```
503s ✓   1,200 transactions per minute ✓   14:32 UTC ✓   14:28 ✓   14:25 ✓   14:38 ✓
API endpoint ✓   API gateway ✓   auth service ✓   root cause ✓
upstream payment provider ✓   dependency failure ✓   roll back ✓
health check ✓   US-47 ✓   US-52 ✓   US-61 ✓   US-68 ✓   CSS custom properties ✓
CDN ✓   graceful error handling ✓   rate-limited ✓   spike ✓   pagination ✓
```

whisper 转写与原文的差异仅为 ASR 自身的表示习惯（`US-47` → "US 47"、
`14:32 UTC` → "1432 UTC"），**语义与用词零偏差**。

### 关键验证：破折号语义反转已被修掉

之前实测 `— but I'm blocked` 被读成 "but unblocked"。试点产物中：

```
原文: Today I'll continue — but I'm blocked.
合成: Today I'll continue, but I'm blocked.
音频: "Today, I'll continue, but I'm blocked"   ← 语义正确 ✓
```

### 试点暴露并已修复的两个问题

1. **站点响应必须显式按 UTF-8 解码**。CoderSlingo 的 `Content-Type` 是
   `text/html` 且**不带 charset**，Dart 的 `http` 包会按 latin1 解码
   `response.body`，UTF-8 的 em dash（E2 80 94）变成 `â\x80\x94`。
   后果：破折号清洗完全失效（合成文本里仍残留乱码破折号）。
   修复：改用 `utf8.decode(response.bodyBytes)`。**这是首轮试点抓到的 bug**——
   如果直接铺量 200-300 轮，所有素材都会带这个问题。

2. **切分的时长估算不能用"固定 7 秒/轮"**。真实的会议轮次从 1.8s（"Two
   points, maybe three."）到 22s（长段技术说明）都有。改用
   `词数 × 400ms + 600ms`（约 150 wpm 的英语会议语速）估算，切分点更准。

### 角色固定音色的实测效果

```
站会:   Lena(Scrum Master)→step_boy / Alex(Backend)→boyinnansheng
        Maria(Frontend)→elegantgentle-female / Sam(QA)→zhixingjiejie
故障:   IC→step_boy / Lead→boyinnansheng / Comms→livelybreezy-female
规划:   Lisa(Product Owner)→elegantgentle-female / Tom(Dev Lead)→boyinnansheng
        Raj(Developer)→cixingnansheng / Mia(Frontend Dev)→dushexiaoyu
```

同一说话人在一个片段内音色恒定 ✓；跨场景的角色（Scrum Master 在站会与
故障排查都是 IC 的 `step_boy`）也一致 ✓。

**一个观察**：`Lisa` 在规划场景里带角色标注 `Product Owner`，而 `Tom` 只写
`Dev Lead`，但 `Tom` 在其它场景里没有角色标注时靠姓名映射兜底——这条兜底
路径在试点里被实际用到了（`Lisa` 后续轮次只有姓名无角色，仍然拿到
`elegantgentle-female`）。**姓名 → 角色的兜底映射是必要的，不是冗余。**

### 铺量产出（2026-10-22）

15 条、111 轮、19.7 分钟音频，覆盖 5 个场景：

| 场景 | 条数 | 时长 | 摘要覆盖 |
|---|---|---|---|
| 站会 | 4 | 45-57s | 0/4（都短于 60s 门槛） |
| 故障排查 | 3 | 98-113s | 2/3 |
| Sprint 规划 | 3 | 63-82s | 2/3 |
| 架构评审 | 2 | 109-112s | 2/2 |
| 客户支持 | 3 | 72-91s | 3/3 |

摘要门槛（60s）按预期把短片段排除在外——站会 4 条全部没有摘要，**这正是设计意图**：短片段一句话说完了，摘要没信息量。

实测两处合成失败（`architecture_..._1_s0` 第 1 轮、`stakeholder_..._1_s0` 第 2 轮）——重试后仍失败，**该片段整体不产出**，符合 spec「重试仍失败则整个片段标记失败并保留诊断，不产出残缺文件」。

### Widget 层测试抓到的三个真 bug（2026-10-22）

写 `page_widget_test.dart` 时暴露的三个问题——**单元测试全绿时它们一个都不会出现**：

1. **页面根必须是 `Material`**：场景项用 `InkWell`，它需要 `Material` 祖先。
   页面根原来是 `Container` → 抛 "No Material widget found" → **整个侧栏不渲染**
   （表现是"场景列表一片空白"）。
2. **`ListView` 在无界高度约束下拿到无穷高**：场景列表原本用 `ListView`，
   实测场景项高度 100000px，文字被挤出可视区。改用
   `SingleChildScrollView` + `Column(mainAxisSize: min)`。
3. **变速按钮平铺会溢出**：四档速度按钮在窄窗口溢出 33px。折叠成一个
   `PopupMenuButton`。

另外 `audioplayers` 在 flutter test 里**没有平台实现**（EventChannel 的 channel 名
带运行期 UUID，根本没法 mock），因此把播放器抽成 `ListeningAudioPlayer` 接口
（`listening_audio_player.dart`），生产用 `AudioPlayerListeningAdapter` 包
audioplayers，测试注入假实现。

### 尚未验证的部分

- **语音的"听感"**：whisper 只能验证**说了什么**，验证不了**听起来像不像真人
  开会**。这需要用户试听（任务 0.7）。这是当前唯一的阻塞项。
- 摘要生成（任务 5.7）尚未实现，故试点产物的 `summary` 为空。
- 播放、悬浮窗、热键、精听模式全部未实现（任务组 6-9）。

## Risks / Trade-offs

- **首版批量铺量可能踩到"合成了但不好听"的坑** → 任务组 0 设为**试点先行**：先烘 3 条（站会/故障/Sprint 各一），逐条 whisper 比对 + 用户试听，把可听性问题清单化后再决定铺量条数与是否调整音色映射与清洗规则。管线（4/5 组）与试点共用同一套代码，试点不是一次性脚本。
- **CoderSlingo 改版导致抓取失效** → 显式映射表 + 结构变化检测（能解析出 0 轮即报"页面结构已变化"而非笼统失败）；素材已落盘，失效只影响增量更新。
- **CoderSlingo 未来收紧抓取政策** → 抓取前检查 `robots.txt`；其当前明确 `Allow: /`。保留出处标注与 CC-BY 标识。若政策变更，切换到 D1 备选的自写剧本路径，管线其余部分不变。
- **TTS 供应商不可用或换绑** → 烘焙通过槽位解析，换绑后重新烘焙即可；已有素材不受影响。首版素材烘焙后完全离线可用。
- **合成音色单调（仅 7 个可信音色）** → 角色固定映射保证辨识度；同性别多角色时用 `speed` 参数（0.9/1.1）做可辨识差异。接受"非母语感"的音色，换来零成本、零额外依赖。
- **断句/破折号类问题可能还有其它形态（逗号、括号、缩写）** → 清洗规则集中在单一函数，只动标点与空白，不动词；且每轮合成后有"空音频/异常时长"检查，异常可重试。已实测逗号、句号、破折号、感叹号均能正确保留填充词（"Um, uh, yeah"）。
- **烘焙耗时与配额** → 30 轮约 71s；首版 20-30 条素材约需 200-300 轮，10-15 分钟一次性烘焙，落在用户可接受范围。进度可见、可中断。
- **子窗口 isolate 的状态同步复杂度** → 只做"主进程持有播放状态、悬浮窗渲染 + 双向 invokeMethod"一条路径，不做通用跨窗口框架。
- **术语本表结构需承载来源** → 复用 `VocabEntries` 既有 `audioUrl`/`phrases`/`sourceContext` 列，**不新增表、不做迁移**；来源信息以 JSON 存在 `sourceContext` 中。
- **"做自己录音导入"被用户期待** → spec 的"多来源共存"只承诺数据模型可扩展；首版 UI 不暴露导入入口，避免半成品功能。

## Migration Plan

无破坏性变更。全部为新增：

- 新增工具目录 `lib/tools/it_meeting_listening/`
- `lib/tools/registry.dart` 新增一条注册
- `lib/main.dart` 新增一个 `WindowKind` 枚举值与对应的子窗口启动分支
- `macos/Runner/AppDelegate.swift` 新增菜单栏项与播放热键注册
- `lib/services/app_paths.dart` 新增两个目录登记（素材目录、缓存目录）
- **无数据库迁移**（`VocabEntries` 表结构不变）

回滚：移除注册表条目与 `WindowKind` 分支即可，素材目录留在磁盘上不影响其它工具。

## Open Questions

- 用户导入自己会议录音的 ASR 源（当前 `stt` 槽位 `stepaudio-2.5-asr` 实测 404，`/v1/audio/transcriptions` 亦 404）——属于后续独立议题，不影响本 change 的首版交付。
- 是否把 CoderSlingo 的开放数据集（643 条 IT 术语，CC-BY）接入术语本作为"预置术语候选"——价值明确但会让术语本首屏变长，属增量功能，可在首版之后追加。
