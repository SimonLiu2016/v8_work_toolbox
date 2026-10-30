## Context

动机见 proposal.md。需求见 `specs/listening-practice-workspace/spec.md`。

现状（实现层面）：

- `ui/it_meeting_listening_page.dart` 是一个 2179 行的单体 `State`，同时持有公开素材索引（`_index`）、排练状态（`_material/_draft/_script/_targetMinutes`）、真实会议状态（`_realMeetings/_selectedMeetingId/_speakers/_realBakeState/_mergeInto/_pendingGroups`）、播放选中（`_selectedScene/_selectedClip`）、筛选（`_selectedSourceId/_typeFilter`）与共享状态行（`_statusMessage`）。
- `RealMeetingPanel` 与 `MaterialImportPanel` 已采用"宿主提供回调"模式，不持有服务。
- 播放由 `ListeningHost` / `ListeningPlayerController` 承担，迷你窗与全局热键共享它——这是可以保留的稳定边界。
- 存储层已支持多场排练：`RehearsalStore` 以 `materialId` 分文件，`listMaterials()` 已存在，排练片段 id 为 `rehearsal_<material>`；仅缺删除接口。`MeetingScript` 持有 `draftId`，可用于判断剧本是否基于当前讲稿。
- `RealMeetingStore.deleteMeeting` 已存在，但界面未暴露。

## Goals / Non-Goals

**Goals:**
- 把单体页面拆成"外壳 + 分区视图 + 控制器"，让每类内容的状态与逻辑各自独立，可单独测试。
- 统一"选中"与"正在播放"两个概念，消除同一会议两套选中状态的问题。
- 不改变磁盘数据格式（除新增字段向后兼容），既有排练与真实会议直接出现在新列表中。

**Non-Goals:**
- 不改变合成管线（ClipBaker / RehearsalBaker / RealMeetingBaker）的内部逻辑与产物格式。
- 不做剧本（ScriptTurn）的手工编辑——只做讲稿编辑。
- 不改迷你播放器与全局热键的界面；只调整它们共享的队列语义（见 D4）。
- 断点记忆的存储与写入时机由 `fix-listening-resume-position` 负责，本变更只消费其结果。

## Decisions

### D1. 外壳 + 三栏布局，组件拆分

```
ListeningWorkspacePage (外壳：标题栏 + 三栏 + 播放条 + 抽屉)
├── WorkspaceHeader           标题、「新建」菜单、词汇表、迷你播放器
├── LibrarySidebar            继续收听卡片 / 我的会议 / 公开素材 / 同步状态
├── 中栏 + 右栏（按 section 切换）
│   ├── PublicSceneView       片段列表 + 来源下拉 + 待生成横幅（两栏，无右侧详情）
│   ├── RealMeetingListView + RealMeetingDetail（概览 | 说话人与音色）
│   └── RehearsalListView   + RehearsalDetail（步骤条 + 步骤内容，含 DraftEditor）
├── WorkspacePlayerBar
└── TranscriptDrawer          共享 TranscriptView
```

选中公开素材场景时右栏折叠，中栏占满——片段短、摘要放在列表项内即可（用户已确认）。

**替代方案**：顶部页签按内容类型分三页。否决：页签之间无法共享"正在播放"的上下文，且公开素材与会议的浏览方式差别大，页签会让播放条/精听的归属变得模糊。

### D2. 状态拆分为控制器

| 控制器 | 职责 | 来源 |
|---|---|---|
| `WorkspaceSelection` | 当前 section（`realMeetings` / `rehearsals` / `scene(MeetingScene)`）、各 section 内选中条目 id、来源筛选 | 原 `_selectedScene/_selectedMeetingId/_selectedSourceId` |
| `PublicLibraryController` | 索引加载、同步、公开素材生成、待生成统计 | 原 `_updateSource/_bake` 中的公开素材部分 |
| `RealMeetingsController` | 会议列表、导入、说话人设定、合成/重新合成/取消、回答插入、删除 | 原真实会议相关方法 |
| `RehearsalsController` | 排练列表、按场加载、四步执行、讲稿编辑保存、删除、目标时长 | 原排练相关方法 + 多场化 |
| `TaskTracker` | 以 `(kind, itemId)` 为键的后台任务进度与结果，供列表标记与短暂提示读取 | 替代 `_statusMessage` |

全部为 `ChangeNotifier`，由外壳持有、经构造参数或 `InheritedNotifier` 下发；视图组件保持"读状态 + 调回调"，沿用现有面板的可测试模式。

**替代方案**：引入 Riverpod/Bloc。否决：项目其余工具未使用，增加依赖与心智负担；`ChangeNotifier` 足够。

### D3. "选中"与"正在播放"分离

- 选中只由 `WorkspaceSelection` 决定，驱动中栏/右栏。
- 正在播放只由 `ListeningHost` 决定，驱动播放条与精听抽屉。
- 选中条目**不会**自动播放；播放只由列表项的播放按钮、详情的播放入口、继续收听卡片触发。
- 点击播放条标题 = 把选中跳到正在播放的内容（反向同步的唯一入口）。

### D4. 队列语义

- 公开素材：队列 = 当前场景（套用来源筛选）的片段，按现有 `_playableIn` 规则跳过无音频片段。
- 排练 / 真实会议：队列 = 单场；上一项/下一项 = 按 `turns[].startMs` 跳到上一轮/下一轮。在当前轮开始 2 秒后按"上一项"回到本轮开头，否则跳到上一轮（常见播放器习惯）。
- 实现位置：在 `ListeningPlayerController` 中增加"轮次导航"模式，按当前 clip 的 `sourceId` 选择行为，使迷你窗与热键自动获得一致语义。

### D5. 合成入口按作用域收敛

- 删除全局 `_bake`。拆为 `PublicLibraryController.bakePending({MeetingScene? scene})`（`scene == null` 即"全部生成"）与 `RealMeetingsController.runPrimaryAction(meetingId)`。
- 原 `_bake` 中"顺手修复真实会议坏记录"（`bake(resume: true)` 只补拼整篇）的行为并入真实会议主操作：状态判定为"整篇音频缺失但分组音频齐全"时，主操作文案为"修复音频"，执行 resume 合成。
- 真实会议主操作状态机：

```
未合成 ──合成语音──▶ 合成中 ──▶ 已合成
                        │           │ 改音色/改名/合并
                        ▼           ▼
                   n 组失败 ◀──── n 组待更新
                   (重试失败的 n 组)  (重新合成 n 组)
整篇缺失 → 修复音频（resume，不调 TTS）
```

### D6. 多场排练

- 列表来源：`RehearsalStore.listMaterials()`；每项摘要由该 material 的 draft/script/索引中的 `rehearsal_<id>` 片段推导出所处步骤。
- 新增 `RehearsalStore.deleteMaterial(id)`：删除 material/draft/script/draft 音频/逐回合缓存，并从素材索引中移除 `rehearsal_<id>`；若正在播放则先停止。
- 目标时长按场保存：在 `RehearsalMaterial` 上新增可选字段 `targetMinutes`（缺省 30，旧数据兼容）；已有剧本时以 `script.targetMinutes` 为初值。
- 排练标题：默认取材料标题，重命名写入 material 的显示名字段（新增可选 `displayTitle`），不改原文件。

### D7. 讲稿编辑与过期判定

- `DraftEditor`：讲稿标题 + 节列表（每节标题单行、正文多行），支持新增/删除/上移/下移；本地维护编辑副本与 dirty 标记。
- 保存：写回 `SpeechDraft`，**生成新的 draft id** 并记录 `editedAt`（新增可选字段）。剧本的 `draftId` 与当前讲稿 id 不一致 ⇒ 剧本步骤显示"已过期"。无需新增修订号字段。
- 离开保护：`RehearsalsController` 暴露 `hasUnsavedDraft`；`WorkspaceSelection` 切换前询问外壳，外壳弹出"保存 / 放弃 / 取消"。
- 重新生成讲稿时若 `editedAt != null` 先确认覆盖。

**替代方案**：自动保存。否决：讲稿保存会让剧本过期，用户应明确知道何时触发了这一后果。

### D8. 精听抽屉

- 右侧推挤式抽屉（宽 420，内容区相应变窄），而非浮层——便于边看列表边看文稿。
- `TranscriptView` 从现有 `_buildTranscriptPanel` 抽出：逐句高亮、术语高亮、点击定位、说话人名、真实会议回答操作（复用 `AnswerComposerDialog` 与现有回答动作）。
- 抽屉开合状态在会话内保留，但播放新内容不会主动打开它（满足既有"默认无文稿"需求）。

### D9. 任务进度与提示

- `TaskTracker` 记录 `{key, label, done, total, error}`；列表项与同步状态区按 key 订阅显示。
- 完成/失败用 SnackBar 一次性提示，失败详情可在条目详情中查看。

### D10. 启动流程

```
initState
  ├─ 并行加载：索引、会议列表、排练列表
  ├─ 读取 lastPlayed（来自 fix-listening-resume-position）
  │    ├─ 内容与音频存在 → selection 跳到它；host.load(paused, offset)
  │    └─ 否 → 最近修改的会议条目 → 第一个非空场景 → 首次引导
  └─ 渲染
```

## Risks / Trade-offs

- [单体页面拆分改动面大，回归风险高] → 分两阶段：先把逻辑抽到控制器、旧 UI 改为读控制器（行为不变、测试保持通过），再替换外壳与视图。
- [队列语义变化影响迷你窗与热键用户习惯] → 只改会议类内容；公开素材保持原有连续播放。
- [讲稿编辑后 draft id 变化，旧逻辑若按 id 关联其他产物会断链] → 实施前检查 `draftId` 的全部引用（剧本、讲稿音频），讲稿音频同样按 id 判定过期。
- [抽屉推挤导致窄窗口下中栏过窄] → 窗口宽度不足时抽屉改为覆盖式。
- [三个现有 widget 测试失效] → 随组件重写，并为控制器补单元测试。

## Migration Plan

- 数据：新增字段（`targetMinutes`、`displayTitle`、`editedAt`）均为可选，旧 JSON 直接可读；不做迁移脚本。
- 界面：新外壳替换 `registry.dart` 中的页面入口；旧面板文件在新视图稳定后删除。
- 回滚：保留旧页面直到验收完成，回滚只需切回入口。
- 旧变更：`add-meeting-material-rehearsal`、`fix-real-meeting-audio-and-naming`、`expand-listening-sources-and-sync`、`decouple-speaker-settings-from-baking` 中未完成的实机验证项在本变更的验收任务中统一完成，并在其 tasks.md 中注明由本变更覆盖。
