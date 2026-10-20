## Context

见 `proposal.md` - Why。这里只记塑造方案的现状约束。

**现状时序**（`lib/main.dart:320-335`）：

```
WindowController.create(hiddenAtLaunch: true)   # registry.dart:396
  → 原生 CreateWindow: setIsVisible(false)      # 窗口隐藏
  → 新引擎 main() 开始跑
_sizeNotebookSubWindowToWorkArea()              # setBounds 铺满工作区
_applyNotebookWindowFallbackBackground()        # setBackgroundColor ← 无效，被 view 盖住
WindowServices.initFor(notebook)                # 5 服务串行，打开 44MB notebook.db
_showNotebookWindowWhenReady()                  # windowManager.show() ← 窗口此刻可见
runAppWithErrorHandling(_NotebookWindowApp())   # 引擎这才启动，首帧更晚
  → Flutter view 不透明黑 layer 裸露            # ← 用户看到的黑屏
  → 首帧 paint
NotebookPage._init() → _refresh()               # 又查一遍 44MB 库
```

**关键约束：`show()` 在 `runApp` 之前调用。** `main.dart:518-527` 的注释明确说这是刻意选择——「等首帧会把可见时机推更晚」。但这个取舍没达成目标：show 在 runApp 之前，仍然留下 `runApp → 首帧` 这段黑窗口裸露期。

**Flutter view 是不透明的。** 子窗口的 `contentViewController` 是 `FlutterViewController`，它的 view layer 在首帧画出前是纯黑。NSWindow 的 `backgroundColor` 被这个不透明层完全覆盖——`_applyNotebookWindowFallbackBackground()` 设的 `0xFFF8FAFC` 用户永远看不到。

**`_applyNotebookWindowFallbackBackground()` 读错了主题。** 它在 `SettingsStore.init()` 之前执行（`main.dart:324` vs `:326`），`themeModeNotifier.value` 还是默认 `ThemeMode.system`，`isDark` 恒为 `false`。

**`_refresh()` 二次冷读。** `NotebookPage._init()`（`notebook_page.dart:152-155`）在 `_store.init()` 之后又调 `_refresh()`，对 44MB 库做了第二次全量查询。这是「空界面 → 数据」的来源。

**二次打开正常。** 关掉再点时，OS 文件缓存已暖，`initFor` 和 `_refresh()` 都快，窗口一出现就带内容。证明启动链本身能跑出完好窗口。

## Goals / Non-Goals

**Goals:**
- 窗口首次可见时已包含渲染好的内容，消除黑屏。
- 删除从未生效的兜底背景色，消除误导性代码。
- 消除 `_refresh()` 对 44MB 库的二次冷读。

**Non-Goals:**
- 不优化 `initFor` 本身的内部耗时（drift 迁移策略、FTS 重建等）——那是另一个 change 的范围。
- 不改变窗口尺寸逻辑（`_sizeNotebookSubWindowToWorkArea` 不变）。
- 不引入首屏 loading 态——首帧后直接 show，不需要中间态。

## Decisions

### D1: `show()` 移到 `addPostFrameCallback` 中，而非 `runApp` 之前

**选择：** 删除 `main()` 中 `runApp` 之前的 `_showNotebookWindowWhenReady()` 调用。改由 `_NotebookWindowApp` 的 `build` 方法中注册 `WidgetsBinding.instance.addPostFrameCallback`，在首帧交付后调用 `windowManager.show()`。

**理由：**
- `addPostFrameCallback` 在首帧 paint 完成后触发，此时 Flutter view 已画出内容，show 不会露出黑 surface。
- 窗口在首帧前保持隐藏（`hiddenAtLaunch: true` 已由 `registry.dart:403` 设置），用户看到的是「几秒后带内容弹出」，与二次打开的体验一致。
- 纯 Dart 改动，不碰原生代码，不触发 codesign 校验链。

**替代方案：**
- *保持 `runApp` 前 show，只优化 `initFor` 速度*：能缩短黑屏时长，但黑屏仍然存在。不满足 spec 的「首帧后可见」。
- *在原生侧推迟 `setIsVisible` 到收到 Dart 信号*：需要 patch `desktop_multi_window`，维护成本落在 vendor 代码上。
- *`windowManager.waitUntilReadyToShow()`*：macOS 实现是空函数（`WindowManager.swift:76-78`），不可用。

### D2: 删除 `_applyNotebookWindowFallbackBackground()` 及其调用点

**选择：** 删除 `main.dart:562-573` 的函数定义和 `:324` 的调用点。

**理由：**
- NSWindow 背景色被 Flutter view 的不透明层完全覆盖，从未生效。
- 它在 `SettingsStore.init()` 之前执行，`isDark` 恒为 `false`，即使能看到也是错的颜色。
- D1 让窗口在首帧前不可见，不存在需要兜底的可见窗口。

**替代方案：**
- *修复主题读取顺序，保留兜底色*：把 `SettingsStore.init()` 提前到 `_applyNotebookWindowFallbackBackground()` 之前。但兜底色仍被 Flutter view 盖住，修了也没用。
- *改为在原生侧设 `NSWindow.backgroundColor`*：同样是 Swift 改动，触发签名链风险，且仍被 view 盖住。

### D3: `_refresh()` 跳过首次加载，复用 `initFor` 已加载的数据

**选择：** `NotebookPage._init()` 中，`_store.init()` 完成后不立即调 `_refresh()`。改为在 `_init()` 中直接读取 `NoteStore` 单例已加载的数据（`groupedNotebooks()` 等），或让 `_refresh()` 接受一个 `skipInitialLoad` 参数跳过首次全量查询。

**理由：**
- `initFor` 中的 `NoteStore.init()` 已经打开了数据库连接并完成了 `beforeOpen`（ALTER TABLE、时间戳归一化、FTS 检查）。`_refresh()` 的查询走的是同一个连接，但 44MB 库的冷盘读在两次查询之间不会因为连接已开就变快——SQLite 的 page cache 有限，第二次全表扫描仍需磁盘 I/O。
- 复用已加载数据不是「跳过查询」，而是「不在首帧关键路径上做第二次全量查询」。可以在首帧交付后再异步刷新。

**替代方案：**
- *保持 `_refresh()` 不变，只靠 D1 消除黑屏*：黑屏消除了，但「空界面 → 数据」仍然存在。用户看到窗口出现后内容延迟填充。
- *把 `_refresh()` 移到 `initFor` 中*：改变了 `WindowServices` 的职责边界，`initFor` 是服务初始化，不是 UI 数据加载。

### D4: 首帧超时兜底

**选择：** 在 `addPostFrameCallback` 注册的同时启动一个定时器（如 10 秒）。若定时器到期时首帧回调仍未触发（异常导致），强制调用 `windowManager.show()` 并记诊断信号。

**理由：**
- `addPostFrameCallback` 若因 build 异常未触发，窗口永远不可见——用户点了「笔记本」毫无反应。
- 超时兜底保证窗口最终可见，遵守 fail-soft 契约。
- 兜底窗口会以小尺寸出现在默认位置——这仍比「完全没反应」好，且只在异常路径发生。

**替代方案：**
- *不设超时兜底*：异常路径下用户永远看不到窗口，违反 spec 的「Window becomes visible even when the first frame is delayed」。

## Risks / Trade-offs

- **首帧回调未触发 → 窗口永远不可见** → 超时兜底（D4）：10 秒后强制 show 并记诊断信号。
- **`_refresh()` 跳过首次加载后数据不一致** → 缓解：`NoteStore` 是单例，`initFor` 和 `_refresh()` 在同一进程中共享同一个实例和连接。跳过的是「重复的全量查询」，不是「跳过数据加载」——数据仍从同一个 `NoteStore` 读取，只是不在首帧关键路径上做第二次全表扫描。
- **首次打开体验从「黑很久」变为「几秒后弹出」** → 这是预期改善，不是风险。用户二次打开时已经是这个体验。

## Migration Plan

纯 Dart 改动，无数据迁移、无 schema 变更。

1. 实现 D1（show 移到首帧回调）、D2（删除兜底背景色）、D3（refresh 跳过首次冷读）、D4（超时兜底）。
2. 本机验证：冷启动点「笔记本」，确认窗口几秒后带内容弹出，无黑屏；确认查词浮窗等其他子窗口行为不变。
3. 回滚：`git revert` 单次提交即可。
