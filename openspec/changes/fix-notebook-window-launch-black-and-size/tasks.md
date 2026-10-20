## 1. 启动链计时与基线观测

- [x] 1.1 在 `lib/main.dart` 的子窗口分支加一次性 debug 级计时日志（`MediaKit.ensureInitialized`、`WindowServices.initFor`、`_sizeSubWindow`、`runApp` 各自耗时），用于验证优化前后的差异，不作为长期保留代码
- [ ] 1.2 记录当前笔记本窗口从点击到首帧的实际耗时作为基线（在计时日志就位后跑一次，数值写进本任务的验证记录）

## 2. 窗口可见时机（design D1）

- [x] 2.1 在 `lib/main.dart` 中新增笔记本窗口的 show/hide 辅助：`hiddenAtLaunch: true` 创建后，由子窗口侧在合适的时机调用 `windowManager.show()`
- [x] 2.2 为 show 路径加超时兜底：若引擎启动链未在约定时间内完成，强制 show 并 `debugPrint` 一条诊断信号（遵守 fail-soft 契约，兜底自身 try/catch）
- [x] 2.3 把 `lib/tools/registry.dart` 的 `NotebookToolDefinition.openNewWindow()` 改为传 `hiddenAtLaunch: true`，并移除主窗口侧的 `await controller.show()`（show 由子窗口自己发起）
- [x] 2.4 确认「窗口已存在则前置」的分支（`window.arguments == 'notebook'`）仍调用 `window.show()`，行为不变

## 3. 尺寸与位置（design D2、D3）

- [x] 3.1 在 `lib/main.dart` 新增 `_sizeSubWindowToWorkArea()`：经 `screen_retriever` 取当前屏幕 `visibleSize`/`visiblePosition`，用 `windowManager.setBounds()` 一次性设定位置与尺寸；不改动现有 `_sizeSubWindow()` 的签名与调用点
- [x] 3.2 把笔记本子窗口分支的顺序调整为「先声明尺寸 → 再 `WindowServices.initFor()` → 再 runApp」，并切到 `_sizeSubWindowToWorkArea()`
- [x] 3.3 在代码注释中记录 `setBounds` 与 `calcWindowPosition` 的屏幕基准不一致这一已知限制（多屏窗口会落到主屏），指向 design 的 open question
- [x] 3.4 确认其余 7 类子窗口分支的 `_sizeSubWindow(...)` 调用逐字未变

## 4. 兜底背景色（design D7）

- [x] 4.1 在笔记本子窗口路径调用 `windowManager.setBackgroundColor(...)`，取当前主题对应的窗口底色（浅色/深色各一），在引擎绘制前生效
- [x] 4.2 确认查词浮窗未被触及——它的窗口必须保持透明（圆角由原生层挖出），不加任何背景色
- [x] 4.3 确认 `_NotebookWindowApp` 首帧后的 `Scaffold(backgroundColor: ...)` 与兜底色一致，不出现可见的色差跳变

## 5. 按需加载多媒体运行时（design D4）

- [x] 5.1 把 `lib/main.dart` 第 286 行的 `MediaKit.ensureInitialized()` 从无条件前缀移出，改为在确实需要多媒体的窗口分支中调用（主窗口、`ai-video-studio`；`agnes-playground` 按实际引用决定）
- [x] 5.2 grep 复核 `package:media_kit` 的全部引用点，确认没有窗口会在未初始化的情况下触碰 `NativeLibrary.path`（已知引用：`ai_video_studio/asset_library_page.dart`、`ai_video_studio/storyboard_board.dart`、`private_player/*`）
- [x] 5.3 确认 `private_player` 走主窗口嵌入（`openInNewWindow` 为 false），主窗口保留调用即可覆盖

## 6. 不再重复一次性工作（design D5、D6）

- [x] 6.1 在 `lib/tools/notebook/note_store.dart` 的 `autoBackfillNotebookStacksFromEvernote()` 中，把「已尝试但印象笔记库无对应 stack」的笔记本 id 持久化到 `config/notebook.json`，下次 `init()` 跳过；写入处注释写清语义（「试过且没结果」而非「不需要」）与手动重试方式
- [x] 6.2 确认已成功回填的笔记本行为不变（有 stack 值的不进 needBackfill，逻辑未改）
- [x] 6.3 在 `lib/tools/notebook/note_database.dart` 的 `_normalizeTextTimestamps()` 前加存在性门禁：无文本形式时间戳行时整组 4 条 UPDATE 跳过；有文本行时行为与现在完全一致
- [x] 6.4 确认门禁用 `EXISTS` 探测而非版本标记——归一化是自愈，外部工具可能再次破坏数据，不能「只做一次」

## 7. 测试与验证

- [x] 7.1 为「已尝试无结果则跳过回填」写单测：配置中已标记的笔记本不再触发外部数据库查询进程；未标记的仍会尝试
- [x] 7.2 为时间戳归一化门禁写单测：无文本行时不执行 UPDATE、有文本行时仍归一化
- [x] 7.3 为新的工作区尺寸计算写单测：窗口 frame 不超过屏幕可见工作区，且位置与尺寸一次设定
- [x] 7.4 跑全量测试，确认失败集合与改动前逐字相同（记忆 `v8worktoolbox-notes` 记录了一批环境依赖型既有失败，用 `git stash` 对比确认与本次改动无关）
- [ ] 7.5 实机验证：点「笔记本」，窗口首次可见即居中且铺满可见工作区，无黑窗、无跳位；对比 1.2 的基线耗时应显著下降
- [ ] 7.6 实机回归：查词浮窗仍是 420×520 贴口气泡且窗口透明；密码库 900×600、运维 1200×800、安全工具箱 1300×850、AI 工坊 1400×900、试炼场 1100×800、单篇笔记 900×650 六个窗口尺寸与改动前一致
