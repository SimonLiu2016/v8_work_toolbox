## Why

点「笔记本」开独立窗口时，窗口先在**屏幕左下角以 800×600 全黑可见**，几十秒后才跳到居中并显示内容。根因不是加载动画，而是时序缺陷：原生侧在 `hiddenAtLaunch: false` 时就 `orderFront + setIsVisible`（`desktop_multi_window` 的 `CreateWindow`），此时新引擎一行 Dart 都没跑；尺寸与居中要等 `main()` 里 5 个串行服务初始化完才声明，首帧更要等到 `runApp`。用户看到的「黑屏时长」= 引擎启动 + 服务链耗时，「跳位」= 尺寸声明那一刻。

同时笔记本窗口的尺寸是硬编码 1100×700（占 1680×1050 屏幕的 44%），而 `openspec/specs/notebook-tool/spec.md` 的「Maximizing notebook sub-window on creation」一直要求铺满屏幕可见工作区——`ff84105` 删掉原生侧无条件 `setFrame(screen.visibleFrame)` 时给了固定尺寸却没重新实现 maximize，全库 `windowManager.maximize` 出现 0 次。spec 与实现已不一致两周。

窗口内容多（三栏 + 可选问答/星图），1100×700 也不够用。

## What Changes

**黑屏与位置（必做）**
- 笔记本窗口改为 `hiddenAtLaunch: true`，由子窗口自己在服务就绪、首帧可交付后才 `show()`；带超时兜底，引擎起不来时窗口仍要出现，不能「点了没反应」。
- 尺寸/居中声明移到 `WindowServices.initFor()` **之前**，让窗口在第一次可见时就是正确的最终位置与大小，消除「跳位」。
- 显式给子窗口设一个不透明背景色，作为引擎未渲染期间的兜底，即使兜底路径被走到也不再是纯黑。
- `MediaKit.ensureInitialized()` 从 `main()` 的无条件前缀改为按窗口类型需要才调用——笔记本窗口不再 dlopen 一整套 mpv/ffmpeg（约 30MB）。
- `NoteStore.init()` 里每次开窗都重跑的两项挪出关键路径或加有效门禁：4 条全表 `UPDATE` 时间戳归一化改为「有文本行才跑」；Evernote stack 回填在确认无法填上时留下已完成标记，不再每次开窗都 `Process.run('sqlite3', …)` 起一个注定失败的子进程。

**尺寸（必做）**
- 笔记本子窗口打开时铺满当前屏幕的可见工作区（排除 Dock 与菜单栏），而非硬编码 1100×700。这是实现 spec 既有要求，不是新需求。

**明确不做**
- 不引入「`runApp` 先跑、服务后台初始化、首屏 loading」的重构。它会动到 `main()` 的 fail-soft 契约（`runApp` 前每个 init 都是黑屏单点），风险与收益不成比例，留给后续 change。

## Capabilities

### New Capabilities
- `window-launch-lifecycle`: 独立子窗口从点击到首帧的生命周期契约——窗口不得在引擎就绪前以错误尺寸可见、可见时必须有非黑兜底、尺寸按屏幕可见区计算。

### Modified Capabilities
- `notebook-tool`: 「Maximizing notebook sub-window on creation」从 spec 有、实现无，变为真实实现（铺满屏幕可见工作区）。

## Impact

**Affected code**
- `lib/main.dart` — 子窗口分派顺序、`MediaKit.ensureInitialized()` 调用点、`_sizeSubWindow()` 改为按屏幕可见区计算并前置、新增 hiddenAtLaunch + show 兜底路径
- `lib/tools/registry.dart` — `NotebookToolDefinition.openNewWindow()` 的 `WindowConfiguration`（`hiddenAtLaunch: true`），`show()` 改由子窗口自己发起
- `lib/tools/notebook/note_store.dart` — `autoBackfillNotebookStacksFromEvernote()` 门禁与完成标记、`_normalizeTextTimestamps()` 调用时机
- `lib/tools/notebook/note_database.dart` — beforeOpen 中归一化 UPDATE 的门禁
- 各子窗口入口的 `_XxxWindowApp` — 首帧后自呼起的 show/hide 逻辑

**Related specs**
- `openspec/specs/notebook-tool/spec.md` — 「Fixed-Width Column Layout and Launch Sizing」的 maximize 场景
- `openspec/specs/app-shell/spec.md` — 「Uncaught async failures leave a diagnostic trace」兜底约束

**Risks**
- `hiddenAtLaunch: true` 若子窗口 show 路径失败，用户点了图标会「没反应」——必须有超时兜底与诊断信号。
- 铺满可见区会影响所有 `openInNewWindow=true` 的工具（密码库、运维、安全工具箱、AI 工坊、试炼场、单篇笔记）。本 change 只改笔记本窗口，其余窗口的尺寸策略不变，但它们共享 `_sizeSubWindow()`，改动需要按窗口类型分流。
- `MediaKit.ensureInitialized()` 延迟后，任何在 `runApp` 之前就触碰 `NativeLibrary.path` 的代码会抛异常。已 grep 确认 `media_kit` 仅被 `ai_video_studio` 与 `private_player` 引用，且都在 widget 层，不在启动链上。
