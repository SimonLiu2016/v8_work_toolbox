## Context

见 `proposal.md` - Why。这里只记塑造方案的现状约束。

**现状时序**（`desktop_multi_window-0.3.1` + `lib/main.dart`）：

```
NotebookToolDefinition.openNewWindow()          # lib/tools/registry.dart:384
  WindowController.create(WindowConfiguration(
    arguments: 'notebook',
    hiddenAtLaunch: false,                       # ← 关键
  ))
  controller.show()
        │
        ▼  原生 CreateWindow（MultiWindowManager.swift:100）
  window.setFrame(NSRect(x: 0, y: 0, w: 800, h: 600), display: true)
  window.orderFront(nil)
  window.setIsVisible(true)                      # ← 窗口此刻可见：左下角 800×600
        │
        ▼  新引擎 main() 才开始跑
  MediaKit.ensureInitialized()                   # ← dlopen mpv/ffmpeg ~30MB，笔记本用不到
  windowManager.ensureInitialized()
  await WindowServices.initFor(WindowKind.notebook)   # 5 项串行
  await _sizeSubWindow(Size(1100, 700))          # ← setSize + center，窗口「跳」到这里
  runAppWithErrorHandling(_NotebookWindowApp())  # ← 首帧
```

**关键约束：原生侧拿不到 arguments。** `CustomWindow` 收了 `configuration` 但不存储，`onWindowCreatedCallback` 只给 `FlutterViewController`。所以「按窗口种类定尺寸」在 Swift 侧做不到——`ff84105` 的 design 已记录这个判断，且至今成立（0.3.1 源码未变）。一切必须由持有着 arguments 的 Dart 侧驱动。

**`main()` 的 fail-soft 契约：** `runApp` 之前每个 `await Xxx.init()` 都是黑屏单点，任何一项抛异常 = 整个窗口黑屏。`WindowServices.initFor` 已按项 try/catch 兜住。这个契约决定了「把服务初始化挪到 runApp 之后」是高风险改动，本设计不碰它。

**`_sizeSubWindow()` 是 8 个窗口共用**（`lib/main.dart` 的 8 个 `_sizeSubWindow` 调用点），改它必须按窗口类型分流，不能一刀切。

**spec 现状：** `notebook-tool/spec.md` 的「Maximizing notebook sub-window on creation」自 `f2c6c0d` 存在，但 `ff84105` 删掉原生无条件铺满后没有对应实现。全库 `windowManager.maximize` 0 次。

**本机数据**（用于判断哪一项值得优化）：`notebook.db` 44MB / 313 篇笔记 / 39 个笔记本；2 个笔记本 stack 为空，其中「微信」在印象笔记库的 `ZSTACK` 也是空 → 回填永远无法填上。

## Goals / Non-Goals

**Goals:**
- 窗口首次可见时即为最终尺寸与位置，消除「左下角黑窗 → 跳位 → 出内容」三段式。
- 即使兜底路径被走到，窗口也不再是纯黑。
- 笔记本窗口铺满屏幕可见工作区（实现 spec 既有要求）。
- 把确认无意义的一次性工作移出每次开窗的路径。
- 改动不破坏其余 7 类子窗口的现有行为。

**Non-Goals:**
- 不把服务初始化移到 `runApp` 之后、不引入首屏 loading 态。那会动 fail-soft 契约，收益/风险不成比例。
- 不改变 `WindowServices` 的显式清单机制（它是「遗漏在代码审查与测试中可见」的设计，值得保留）。
- 不优化服务初始化本身的内部耗时（如 drift 迁移策略、FTS 重建），只做「不重复做无进展的工作」。
- 不引入新的窗口管理依赖；继续用 `window_manager` + `desktop_multi_window`。

## Decisions

### D1: `hiddenAtLaunch: true` + 子窗口自呼起，而非原生侧改显示时机

**选择：** 笔记本窗口的 `WindowConfiguration` 改 `hiddenAtLaunch: true`，由子窗口在 `runApp` 前（或首帧后）自己 `windowManager.show()`。配一个超时兜底。

**理由：**
- 原生侧在 `setIsVisible` 时没有任何 Dart 信号可用；能驱动「何时可见」的只有 Dart 侧。
- `windowManager.show()` 在 macOS 的实现是 `setIsVisible(true)` + `makeKeyAndOrderFront` + `NSApp.activate`。对笔记本窗口，激活 App 是用户点了「打开笔记本」后的预期结果（`lookup_window.dart:97-98` 的注释已确立这个区分）。
- 不动原生代码意味着不动 `codesign` 校验链——`flutter-macos-deploy-pitfalls` 记忆里记着「增量构建签名失效 → Keychain 拒绝」的坑，纯 Dart 改动规避整条风险。

**替代方案：**
- *在原生侧把 `setIsVisible` 推迟到收到 Dart 信号后*：需要给 `desktop_multi_window` 打补丁或 fork，且仍需 Dart 发信号，复杂度更高、维护成本落在 vendor 代码上。
- *保持 `hiddenAtLaunch: false`，只把尺寸声明提前*：能消除「跳位」，但窗口仍会以黑/透明表面出现一段时间。不满足 spec 的「非黑兜底」。
- *`waitUntilReadyToShow()`*：macOS 实现是空函数（`WindowManager.swift` 的 `waitUntilReadyToShow()` 无操作），不可用。

### D2: 尺寸声明移到 `WindowServices.initFor()` 之前

**选择：** 子窗口分支先 `_sizeSubWindow(...)`（或新的 `_sizeSubWindowToWorkArea()`），再 `initFor(...)`。

**理由：** `windowManager.setSize/center` 只依赖 `windowManager.ensureInitialized()`（已在 `main()` 第 280 行完成，位于所有子窗口分派之前），不依赖任何服务。顺序可换，且越早声明，窗口一旦可见就越是终态。

**替代方案：**
- *保持 init 在前、尺寸在后*：保留「跳位」，与 D1 的「首次可见即终态」目标矛盾。

### D3: 铺满可见工作区用 `setBounds` 精确计算，而非 `windowManager.maximize()`

**选择：** 通过 `screen_retriever` 取当前屏幕的 `visibleSize`/`visiblePosition`，算出窗口 frame 后用 `windowManager.setBounds()` 一次性设定位置与尺寸。

**理由：**
- `windowManager.maximize()` 在 macOS 上是 `mainWindow.zoom(nil)`（`WindowManager.swift:156`）。`zoom` 的语义是「在用户尺寸与标准尺寸间切换」，不是「铺满可见区」；且它改变的是窗口的 zoomed 状态，用户之后点绿箭头会回到一个未知尺寸。spec 要求的是「fill the visible work area」，用 `zoom` 实现会在语义上打折扣。
- `setBounds` 走 `WindowManager.setBounds`，宽度高度与 topLeft 都可控，一次调用同时定位置和尺寸，不存在 setSize 后 center 的中间态。

**替代方案：**
- *`windowManager.maximize()`*：语义不符（zoom 而非铺满），且后续用户交互行为不可预期。
- *恢复原生侧 `setFrame(screen.visibleFrame)`*：原生侧拿不到 arguments，会把查词浮窗等所有子窗口一起撑满——这正是 `ff84105` 修掉的 bug。

**已知坐标陷阱（记录，不在本 change 修）：** `window_manager` 与 `screen_retriever` 的 `NSRect.topLeft` 扩展都用 `NSScreen.screens[0].frame` 做坐标换算。单屏无损；多显示器时窗口会被算到主屏。`calcWindowPosition` 用光标所在屏算位置、`setBounds` 用 `screens[0]` 换算 y，两条路径的屏幕基准不一致。本 change 只服务单屏正确性，多屏留作 open question。

### D4: `MediaKit.ensureInitialized()` 改为按窗口类型按需调用

**选择：** 从 `main()` 的无条件前缀，改为在需要多媒体的窗口分支里调用（`ai-video-studio`、`agnes-playground` 若需要、以及主窗口）。笔记本、密码库、运维、安全工具箱、查词、单篇笔记不调。

**理由：** grep 确认 `package:media_kit` 仅被 `ai_video_studio/`（`asset_library_page.dart`、`storyboard_board.dart`）与 `private_player/` 引用，全在 widget 层，不在任何 `init()` 链上。`NativeLibrary.path` 在未初始化时抛异常——只要没有窗口在不初始化的情况下触碰 media_kit API，延迟就是安全的。

**风险控制：** `private_player` 目前不在子窗口列表里（`openInNewWindow` 为 false，嵌入主窗口），主窗口保持调用即可覆盖它。

**替代方案：**
- *保持无条件调用*：每次开任何子窗口都 dlopen ~30MB 框架，笔记本窗口白付这笔成本。
- *做成完全惰性（首次用到时才初始化）*：需要改 `media_kit` 的调用点或加包装，侵入第三方包的使用方式，收益与侵入不成比例。

### D5: Evernote 回填加「已尝试」持久标记，而非保留内存缓存

**选择：** 把「已确认无法回填」的笔记本 id 写入 `config/notebook.json`（复用 `SettingsStore` 的 tool config 机制，与 `ftsTokenizerVersion` 同一位置同一种做法），下次 `init()` 直接跳过。

**理由：**
- 内存缓存无效：子窗口是独立进程，每次打开都是全新进程（`desktop_multi_window` 每个窗口一个 `FlutterDartProject`）。
- `config/notebook.json` 已有先例：`_migrateFtsTokenizerIfNeeded` 就用 `ftsTokenizerVersion` 版本标记做「只跑一次」，同一文件同一机制，不引入新的持久化位置。
- 标记的语义是「试过且没结果」，不是「不需要」——若用户之后装了印象笔记，删掉这个 key（或升级一个版本号）即可重试。这一点要写进注释，否则将来会变成「为什么我的 stack 一直不回填」的新谜题。

**替代方案：**
- *在数据库加列标记*：要改 drift schema + 迁移，比一个 config key 重得多。
- *把回填整体改成用户手动触发*：行为变更超出本 change 范围（spec 的「Automatic stack backfill on startup」要求自动）。

### D6: 时间戳归一化加存在性门禁

**选择：** 4 条 `UPDATE ... WHERE typeof(col)='text'` 之前先跑一次 `SELECT EXISTS(...)`，无文本行则整组跳过。

**理由：** 归一化是自愈，不是常规维护；正常情况下（本机已全部为 integer）这 4 条每次开窗都是全表空扫。加一道 `EXISTS` 把成本降到一次索引探测，且不改变自愈语义——有文本行时行为与现在完全一致。

**替代方案：**
- *也加版本标记*：与 D5 同样的思路，但归一化可能由外部工具再次破坏（记忆 `drift-text-timestamp-pitfall` 记着这类事故），不能「只做一次」；存在性门禁才是正解。

### D7: 兜底背景色由 Dart 侧声明，不改原生

**选择：** 在子窗口分支（或 `_XxxWindowApp` 的 `build` 之前）调用 `windowManager.setBackgroundColor(...)`，取当前主题对应的窗口底色。

**理由：** 与 D1 同源——纯 Dart 改动不碰签名链。`window_manager.setBackgroundColor` 在 macOS 上直接设 `NSWindow.backgroundColor`（`WindowManager.swift:231`），在引擎绘制前就生效。

**注意：** 不能对查词浮窗这么做——它的窗口是透明的，圆角由 macOS 原生层挖出（`lookup_window.dart:43-47` 的注释明确警告过改成 `context.bg*` 会盖掉透明通道）。本 change 只对笔记本窗口设。

**替代方案：**
- *在 `MainFlutterWindow.swift` 的 `onWindowCreatedCallback` 里统一设*：那是个 Swift 改动，触发 D1 里说的签名链风险；且该回调拿不到 arguments，无法区分查词浮窗（必须透明）与笔记本（必须不透明）。

## Risks / Trade-offs

- **`hiddenAtLaunch: true` 后子窗口 show 失败 → 用户点了没反应** → 超时兜底：`runApp` 前起一个定时器，若 X 秒内未 show 则强制 show 并记诊断信号。兜底本身也要 try/catch，遵守 fail-soft 契约。兜底窗口会以小尺寸出现在默认位置——这仍比「完全没反应」好，且只在异常路径发生。
- **`setBounds` 的屏幕基准不一致（D3 已知陷阱）** → 本 change 只在单屏验证。多显示器用户的窗口可能落到主屏。缓解：design 记录为已知限制 + open question，不在本 change 里改 `topLeft` 扩展（那需要 fork 或 patch 第三方包）。
- **D4 延迟 MediaKit 后，若有遗漏的调用点会在运行时抛** → 缓解：grep 已确认 `media_kit` 引用范围；实现期在需要它的窗口分支里显式调用，并保留 `try/catch`（`MediaKit.ensureInitialized` 自身已 catch 并 print，不会抛）。
- **D5 的标记让「以后装了印象笔记也不会自动回填」** → 缓解：标记写入处写清语义与手动重试方式；`ftsTokenizerVersion` 的版本号机制可复用（bump 即全量重试）。
- **`_sizeSubWindow()` 被 8 类窗口共用，改错影响面大** → 缓解：新增专用函数而非改原函数签名，笔记本分支单独切到新函数；其余 7 类的调用点保持逐字不变，使 diff 可审查。
- **测量边界**：本机能确证时序与各项成本量级，但「黑屏几十秒」的精确归因（各 init 占多少 ms）未实测。缓解：实现期在启动链加一次性计时日志（debug 级别），随任务一起验证，不作为长期保留代码。

## Migration Plan

纯 Dart 改动，无数据迁移、无 schema 变更。

1. 实现（见 `tasks.md`），按 D1→D2/D3→D7→D4→D5/D6 顺序，每步可独立验证。
2. 本机验证：点「笔记本」，确认窗口首次可见即居中且铺满可见区、无黑窗、无跳位；确认查词浮窗仍是 420×520 贴口气泡（未被铺满）；确认密码库/运维/安全工具箱/AI 工坊/试炼场/单篇笔记六个窗口尺寸与改动前一致。
3. 回滚：`git revert` 单次提交即可，无数据副作用（D5 的 config key 多余但无害）。

## Open Questions

- **多显示器下的屏幕基准**：`window_manager` 的 `setBounds` 用 `NSScreen.screens[0]` 换算 y，而 `calcWindowPosition` 用光标所在屏。多屏用户的窗口会被算到主屏。修它需要 patch 第三方包或改为原生侧实现——超出本 change 范围，用户单屏所以不阻塞。是否值得单独开 change 取决于是否有多屏使用场景。
- **其余 7 类子窗口是否也要铺满可见区**：spec 只为笔记本规定了 maximize。运维工具（多面板）、AI 工坊（分镜看板）内容也密集，但它们没有对应 spec 要求。本 change 只改笔记本，其余保持现状；若后续要统一，应各自先立 spec。
