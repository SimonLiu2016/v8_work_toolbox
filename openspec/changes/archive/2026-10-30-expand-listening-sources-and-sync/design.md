## Context

见 proposal.md - Why。此处只记录**实测得到、且直接约束实现方式**的事实。

### 首版实现的现状

- 内容来源写死为 `CoderSlingoSource` 一个具体类；素材库、烘焙器、播放器直接依赖它。
- 映射表只收录 5 个栏目、导入其**每个栏目的前 4 块**，共 15 条已烘焙素材（另有 18 条 0 秒占位记录——早期"只写本次产出到索引"的 bug 留下的残骸）。
- `ClipIndex` 的结构是 `{version, generatedAt, clips}`，**没有"每个来源/栏目的同步状态"**。因此「更新素材」只能全量重抓 + 全量重烘焙。
- `ClipSource` 只有 `site`/`pageUrl`/`column`/`license`，**没有稳定的源标识**；`Clip.id` 是 `{scene}_{column}_{block}`，也不含源标识。
- 迷你播放窗用 `windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false)` 隐藏了整个标题栏，**没有任何关闭入口**。窗口常驻置顶、失焦不自动关，用户只能重启应用。

### 站点内容的实测全貌（2026-10-22）

CoderSlingo 的 `/exercises/` 下有 **176 个分类**、全站 9708 个 exercise 页面、`sitemap.xml` 有 **14212 个条目且全部带 `lastmod`**。

听力区 18 个栏目 / 95 个页面，按内容形态分两类：

| 形态 | 栏目 | 页面数 | transcript 块 |
|---|---|---|---|
| **transcript**（连续多轮对话，可直接切轮次） | standup-dialogues / incident-calls / sprint-planning / architecture-talks / customer-support-calls / job-interviews / onboarding-calls / product-demos / tech-talks / technical-interviews | 10 | **34** |
| **passage/quiz**（选择题，题干里引用对话） | conference-panels / engineering-all-hands / executive-briefings / pair-programming-dialogues / vendor-demo-calls / vendor-evaluation-calls / british-american-accents / pronunciation-awareness | 8 | 0 |

新纳入的 5 个栏目实测确认仍是**带角色标注的连续多轮对话**（与首版 5 个栏目同构）：

```
job-interviews       Interviewer: "Tell me about a time you had to deliver a project under significant pressure..."
onboarding-calls     Sarah: "Welcome to the team, Tomasz! ... Leo's going to walk you through the tech stack..."
product-demos        Sales Engineer (Tom): "Thanks for having us. Today I'll show you three things..."
tech-talks           Speaker: "...so let me challenge the conventional wisdom here..."
technical-interviews Interviewer: "Let's start with a system design question. How would you design a URL shortener?"
```

**但站点的会议场景远不止听力区**：`/exercises/meetings/`（17 个子页）、`/exercises/incident-response/`（13）、`/exercises/code-review/`（6）、`/exercises/speaking/`（13）等分类里还有大量会议场景内容——但它们是 **quiz 形态**（见 D5 的取舍）。

### quiz 形态能抽出多少对话（实测）

抽 8 个会议类子页，用正确的兄弟节点切分（`exercise-item` 是平铺兄弟，不是嵌套 div）解析：

```
meetings/alignment-meetings        20 题  含"Name (Role) says/asks"  6   含引语  12
meetings/incident-review-meetings  19 题  含角色对话                0   含引语  15
meetings/standup-exercises         19 题  含角色对话                0   含引语  14
meetings/one-on-ones               19 题  含角色对话                3   含引语  17
meetings/remote-meeting-challenges  39 题  含角色对话                0   含引语  29
meetings/technical-discussions      15 题  含角色对话                0   含引语  11
meetings/architecture-reviews      20 题  含角色对话                0   含引语   6
meetings/sprint-planning           19 题  含角色对话                0   含引语   8
```

## Goals / Non-Goals

**Goals:**

- 工具显示名与内容定位脱钩于"IT 会议"，改用「听力练习」。
- 迷你窗有显式关闭入口，且关闭不终止播放、可重新唤出。
- 来源可插拔：新增来源不触碰素材库/烘焙器/播放器/界面。
- 素材标识在多来源下唯一，来源归属可追溯（素材、文稿、术语收藏三处一致）。
- 更新走增量：未变更的栏目零网络请求、零 TTS 调用。
- 覆盖 CoderSlingo 全部 10 个 transcript 形态栏目（34 块）。

**Non-Goals:**

- 不做 quiz 形态内容的导入（D5 有详细取舍）。
- 不改 `EdgeTtsEngine`。
- 不做浏览器插件形态。
- 不做学习统计、打卡、排名。
- 不改既有场景枚举的 id（只增不减）。
- 不改工具 id、目录名、素材目录名。

## Decisions

### D1: 工具只改显示名，不动 id 与目录

**决策**：`registry.dart` 的 `title` 改为「听力练习」；`kToolIdItMeetingListening`、`lib/tools/it_meeting_listening/`、`AppPaths.itMeetingListeningDir` **全部保持**。

**理由**：id 是持久化键。术语本里已有收藏条目的 `sourceContext.tool = 'it-meeting-listening'`，`vocab_book_page.dart` 的回听跳转靠它匹配。改 id 会让既有收藏集体失效，而收益仅为"名字和 id 对齐"。

**备选与取舍**：*连 id 一起改成 `listening-practice`* —— 更整齐，但要写数据迁移（扫全库 `sourceContext` 改字段值），且术语本里可能有用户手动编辑过的条目。收益不抵成本。

### D2: 迷你窗关闭 = 隐藏，不终止播放

**决策**：迷你窗内加一个关闭控件，点击后**隐藏窗口**（`windowManager.hide()`），播放继续。`ListeningHost.closeMiniWindow()` 已有 `hide()` 实现，只是没有入口。

**理由**：这正是既有 spec「关闭悬浮窗不终止播放」的要求——播放状态在主进程（design D7 的 D7 决策），窗口只是视图。隐藏视图不该销毁状态。

**备选与取舍**：*关闭 = 真正 destroy 窗口*（`WindowController` 没有直接的 destroy，得靠原生关窗）—— 会让 `WindowMethodChannel` 的双向配对断开，重开时通道要重新注册，且播放状态仍需保留。隐藏更简单且语义正确。

**重新唤出的三个入口**（缺一不可，否则用户会"关掉就再也开不了"）：
1. 主窗口工具页的「迷你播放器」按钮（已有）
2. 菜单栏「会议音频播放器」（已有）
3. 关闭后再点主窗口按钮时，host 检测到窗口已存在则前置而非新建

### D3: 抽 `ListeningSource` 抽象层

**决策**：定义统一接口，`CoderSlingoSource` 降级为其一个实现。

```
                  ┌──────────────────────────────────────┐
                  │  ListeningSource (抽象)              │
                  │  id / displayName / license          │
                  │  discoverColumns() → List<SourceColumn>
                  │  fetchDialogues(column) → List<Dialogue>
                  │  changeTokenFor(page) → String?      │
                  └────────────────┬─────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
        CoderSlingoSource              <未来的来源>  /  用户录音
        (站点特有逻辑全在内部)          (各自实现同一接口)
```

**理由**：现在上层直接依赖 `CoderSlingoSource` 的静态方法与常量（`columns` 映射表、`siteName`）。加第二个来源时，映射表、许可、URL 拼接这些"站点特有"的东西会渗进上层。

**关键设计点**：**场景映射放在来源内部**。`standup-dialogues → MeetingScene.standup` 是"这个站点的哪个栏目对应我们哪个场景"，属于站点知识；而 `MeetingScene` 枚举是**我们自己的**分类，不随站点变。来源内部维护 `slug → MeetingScene` 的映射，上层只看 `MeetingScene`。

**备选与取舍**：*用配置表（JSON/YAML）描述来源*——更灵活，但引入配置解析与校验，对第二个来源尚未落地的情况是过度设计。等真有第三个来源再考虑。

### D4: `sourceId` 进模型，`Clip.id` 加源前缀

**决策**：
- `ClipSource` 增 `sourceId`（稳定标识，如 `coderslingo`），与 `site`（展示名）并存
- `Clip.id` 改为 `{sourceId}_{sceneId}_{columnSlug}_{block}`，如 `coderslingo_standup_standup-dialogues_0`
- **旧素材一次性重烘焙迁移**

**理由**：多源时 `site` 是展示名（可能重名、可能改名），不能当键。`Clip.id` 同时是音频文件名与文稿文件名的主干——两个来源都有 standup 场景就会撞名，音频互相覆盖。

**为什么用重烘焙而不是数据迁移**：现有索引 33 条里只有 15 条有音频，18 条是 0 秒占位（早期 bug 残骸），本来就要清。重烘焙 111 轮 ≈ 2 分钟，比写迁移脚本更省事且能顺手验证新 id 规则。

**备选与取舍**：*给 id 加源后缀而非前缀* —— 前缀让"按来源筛文件"能用 glob 前缀匹配（`coderslingo_*`），后缀不行。选前缀。

### D5: 不做 quiz 形态内容的导入

**决策**：首版只导入 10 个 transcript 形态栏目的 34 块，**不做**从 quiz 题干抽取对话碎片。

**理由**（实测数据支撑）：

```
transcript 形态  →  天然的连续多轮对话，有说话人、有轮次边界、有真实音频时长
quiz 形态        →  题干里的 "Sarah (Backend) asks: '...'" 是孤立一句
```

quiz 形态的问题不是"抽不出来"，而是**抽出来的东西不构成对话**：
- 一题一句，同一场景的 20 句之间没有上下文衔接
- 说话人不连续（Sarah 出现一次就消失）
- 没有音频时长可用（站点不提供）
- 需要额外设计"碎片 → 片段"的组装规则，而这个规则会产出**人造的连贯性**——用户听到的是拼接出来的假会议，比真实的短对话更糟

而它换来的覆盖是 176 个分类的词汇题，其中真正含会议对话的比例实测 30-75%——**收益是"多几个孤立句子"，代价是"碎片化的伪对话"**。

**备选与取舍**：*抽取 quiz 题干中的引语，作为"单句跟读"素材类型*——技术上可行（我已有解析器），但那不是听力材料，是发音练习。与本工具的定位（听懂会议）不符。**列为未来的独立功能，不在本 change。**

### D6: 两级变更检测——`sitemap.xml` 的 `lastmod` + 对话文本哈希

**决策**：变更检测分两级，两级各挡掉一半的浪费：

```
第一级（零页面请求）：sitemap.xml 的 lastmod
    ↓ 站点没重建 → 该栏目整个跳过，连页面都不抓
第二级（页面已抓）：解析后的对话文本哈希
    ↓ 文本没变 → 跳过烘焙，保留现有音频与文稿
```

实测：`sitemap.xml` 14212 个条目**全部带 `lastmod`**，但**粒度是站点构建时间**——

```
listening 区 95 页     lastmod 全是 2026-10-13T16:15:19.000Z（1 种）
meetings 18 页        同上（1 种）
speaking 117 页       同上（1 种）
全站 145 种 lastmod，其中 3112 条是 2026-10-13 之前的（多为 blog 文章）
```

**这意味着 `lastmod` 是"站点是否重建过"的信号，不是"某栏目是否改过"的信号。** 站点一重建，全部 9708 个 exercise 页的 lastmod 一起变。

**所以第一级挡的是"用户反复点更新但站点没动"这个最常见的场景**（实测是绝大多数）——这正是当前实现最大的浪费来源：现在每次点更新都要重抓 + 重烘 111 轮。

**第二级挡的是"站点重建了但某个栏目内容其实没动"**——重建后重抓 34 块文本，算哈希，只对真正变了的栏目重烘 TTS。这才是省配额的关键（烘焙 111 轮 ≈ 2 分钟 + 配额消耗，而重抓 34 个页面只要几十秒）。

**为什么两级都要**：
- 只有 lastmod：站点一重建就全量重烘，用户看着 TTS 配额哗哗地掉
- 只有文本哈希：每次都要重抓全部页面才能算哈希，"没变化"也付出了全部网络成本
- 两级组合：**没重建时零请求零 TTS；重建了只重烘真正变了的**

**备选与取舍**：
- *只做第一级*——实现简单，但站点每次重建都全量重烘，代价明显
- *只做第二级*——每次更新都要全量重抓，"没变化"也付了全部网络成本
- *HTTP `Last-Modified` 响应头*——逐页发 HEAD，14212 次请求太贵
- *每页单独记哈希*——粒度更细，但站点的 lastmod 已经是构建级，页面级哈希收益递减

**退化路径**：若某来源既不提供变更标识、其内容又无法稳定哈希，则该来源每次全量抓取 + 全量烘焙，并在界面明确标注"该来源不支持增量更新"（写进 spec）。

### D7: 同步状态独立于素材存储

**决策**：新增独立的同步状态文件，记录每个 `{sourceId, columnSlug}` 的：上次同步时间、上次的 `lastmod`、最近失败原因、累计失败次数。**与素材目录分开**。

**理由**：素材是**产物**（会被重烘焙覆盖），同步状态是**与环境交互的历史**（上次同步到哪了）。两者生命周期不同：重烘焙不该让系统以为"这个栏目没同步过"而全量重抓。

**备选与取舍**：*把状态塞进 `index.json`*——省一个文件，但索引是全量覆盖写的（首版踩过"只写本次产出导致其它场景条目消失"的坑），状态混进去有同样风险。

### D8: 增量更新的编排粒度是"栏目"

**决策**：比对单位是**栏目**（一个栏目一个 `lastmod`），不是单个页面。

**理由**：
- CoderSlingo 的栏目页面共用一个 `lastmod`（实测同一栏目的所有子页 `lastmod` 相同）——页面级比对不会更精确
- 栏目级重抓的实现简单得多（抓取接口本来就是按栏目的）
- 一个栏目 3-5 块，整体重抓的成本是 3-5 轮 TTS，可接受

**备选与取舍**：*页面级增量*——需要重写抓取接口为"按 URL 抓单页"，且实际收益为零（同栏目 lastmod 相同）。

### D9: 场景枚举扩展到 10 个

**决策**：`MeetingScene` 新增 5 个：`jobInterview`（面试）、`onboarding`（新人入职）、`productDemo`（产品演示）、`techTalk`（技术演讲）、`technicalInterview`（技术面试）。既有 7 个 id 不变。

**理由**：新纳入的 5 个栏目内容真实且形态一致，不纳入是浪费。技术面试与行为面试虽同属"面试"，但一个是系统设计问答、一个是行为 STAR 场景，语体差异大，合成时值得分开。

**备选与取舍**：*全部塞进一个"面试"场景*——省枚举，但用户想专门练系统设计问答时找不到。

## Risks / Trade-offs

- **`lastmod` 是构建时间而非内容时间，增量收益比预期小** → 实测确认：listening 区 95 页、meetings 18 页、speaking 117 页的 `lastmod` **全部相同**（`2026-10-13T16:15:19.000Z`，站点构建时刻）。所以第一级只能挡"站点没重建"，挡不住"重建了但某栏目没改"。**第二级（对话文本哈希）才是省 TTS 配额的关键**——这决定了 D6 的两级设计不能省掉第二级。
- **重建后仍要重抓 34 个页面** → 抓取成本（几十秒）远低于烘焙（111 轮 TTS ≈ 2 分钟 + 配额），取舍划算。
- **重烘焙迁移会消耗 TTS 配额** → 111 轮 ≈ 2 分钟、约 2000 字文本量。一次性成本。
- **多源抽象可能过度设计**（只有一个源） → 抽象本身是薄接口（4 个方法），成本低；真正的收益在第二个源落地时才兑现。接受这个"暂时用不上"的状态——因为用户明确说了"后面可能增加其他的网站"。
- **场景枚举增长到 10 个会让侧栏变长** → 首版实现已改成"只列有素材的场景"，侧栏长度随素材而非枚举增长。
- **quiz 形态的素材长期缺席** → 用户可能问"为什么站会上讲 incident review 的内容没有"。在界面或文档里说明"仅收录含完整对话的栏目"。

## Migration Plan

1. 新增 `sourceId` 字段与新 `Clip.id` 规则（默认值 `coderslingo`，保证旧数据可读）
2. 一次性重烘焙：清空素材目录与索引，按新规则重建（111 轮 ≈ 2 分钟）
3. 术语本 `sourceContext` 中的 `tool` 字段不变（工具 id 未变），无需迁移；仅新增 `sourceId` 字段（新收藏带，旧收藏缺省为 `coderslingo`）
4. 回滚：素材目录与索引是纯产物，删掉重烘焙即可；同步状态文件可安全删除

## Open Questions

- 对话文本哈希的规范化方式（是否包含说话人标注、场景说明行）——会影响"内容变了"的判定粒度。实现时以"解析后的轮次文本 + 说话人"为准。
- 用户自己的会议录音（`live_translator` 那个 change 的方向）要不要作为**第一个非 CoderSlingo 的来源**接进来？它的形态是本地音频 + ASR，与网页来源的"抓取"模型差异大，可能需要一个不同的接口方法。留待实现时决定。
- 用户自己的会议录音（`live_translator` 那个 change 的方向）要不要作为**第一个非 CoderSlingo 的来源**接进来？它的形态是本地音频 + ASR，与网页来源的"抓取"模型差异大，可能需要一个不同的接口方法。留待实现时决定。
