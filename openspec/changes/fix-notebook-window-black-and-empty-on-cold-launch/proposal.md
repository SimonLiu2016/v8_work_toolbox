## Why

笔记本独立窗口冷启动时呈现三段劣化：**黑屏很长一段时间 → 空界面 → 数据出现**。`fix-notebook-window-launch-black-and-size` 已把 `show()` 移到 `runApp` 之前，但 Flutter view 的不透明黑 layer 在首帧画出前仍然裸露——用户看到的黑屏是结构性的，与数据加载快慢无关。同时 `_applyNotebookWindowFallbackBackground()` 在 `SettingsStore.init()` 之前执行，`themeModeNotifier` 还是默认 `ThemeMode.system`，`isDark` 恒为 `false`，且 NSWindow 背景色被 Flutter view 完全盖住，兜底从未生效。

二次打开（关掉再点）时窗口几秒后带内容弹出，证明启动链本身能跑出完好窗口——慢只在冷盘首次读 44MB `notebook.db` 时，且这段冷读在关键路径上发生了两遍（`initFor` 一遍、首帧后 `_refresh()` 一遍）。

## What Changes

- **`show()` 移到首帧之后**：`_NotebookWindowApp` 用 `addPostFrameCallback` 在首帧交付后再调用 `windowManager.show()`。窗口永远不会露出黑 surface——要么隐藏（启动链在跑），要么一出现就是画好的内容。
- **删除无效的兜底背景色**：`_applyNotebookWindowFallbackBackground()` 被 Flutter view 的不透明层完全盖住，且读错了主题。删除该函数及其调用点。
- **`_refresh()` 不在首帧后重复冷读**：`NotebookPage._init()` 在 `_store.init()` 之后又调 `_refresh()`，对 44MB 库做了第二次全量查询。改为复用 `initFor` 已加载的数据，或让 `_refresh` 跳过首次加载。

## Capabilities

### New Capabilities

- `window-first-frame-visibility`: 独立子窗口的可见时机 MUST 在引擎首帧交付之后，而非 `runApp` 之前。窗口在首帧前保持隐藏，首帧完成后才 `show()`。这取代 `window-launch-lifecycle` 中「show 在 runApp 之前」的旧契约。

### Modified Capabilities

- `window-launch-lifecycle`: 「Window visibility follows engine readiness」的语义从「服务初始化完成后 show」改为「首帧交付后 show」——`runApp` 之前 show 仍会露出 Flutter view 的不透明黑 surface，必须等到 `addPostFrameCallback` 触发。
- `window-launch-lifecycle`: 「Visible window has a non-black fallback surface」整条需求删除——NSWindow 背景色被 Flutter view 完全覆盖，该兜底机制从未生效，保留只会误导后续维护者。

## Impact

**Affected code**
- `lib/main.dart` — 删除 `_applyNotebookWindowFallbackBackground()` 及其调用点；`_showNotebookWindowWhenReady()` 从 `runApp` 之前移除，改由 `_NotebookWindowApp` 首帧回调触发
- `lib/tools/notebook/ui/notebook_page.dart` — `_init()` 中 `_refresh()` 的二次冷读优化

**Related specs**
- `openspec/specs/notebook-tool/spec.md` — 「Maximizing notebook sub-window on creation」不受影响，尺寸逻辑不变
- `openspec/specs/window-launch-lifecycle/spec.md` — 上述两条需求变更

**Risks**
- 首帧回调若因异常未触发，窗口永远不可见 → 保留超时兜底：`addPostFrameCallback` 注册一个定时器，若 N 秒内首帧未到则强制 `show()` 并记诊断信号
- `_refresh()` 跳过首次加载后，若 `initFor` 的数据与页面期望不一致，需确认 `NoteStore` 单例状态在子窗口进程中正确共享
