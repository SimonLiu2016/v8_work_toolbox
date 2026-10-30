## 1. Show 移到首帧回调（design D1）

- [x] 1.1 在 `_NotebookWindowApp` 的 `build` 方法中注册 `WidgetsBinding.instance.addPostFrameCallback`，首帧交付后调用 `windowManager.show()`
- [x] 1.2 从 `main()` 的 notebook 分支中移除 `await _showNotebookWindowWhenReady()` 调用（`:330`），保留函数定义备用或删除
- [x] 1.3 确认 `registry.dart:403` 的 `hiddenAtLaunch: true` 不变——窗口在首帧前保持隐藏

## 2. 删除无效兜底背景色（design D2）

- [x] 2.1 删除 `main.dart:562-573` 的 `_applyNotebookWindowFallbackBackground()` 函数定义
- [x] 2.2 删除 `main.dart:324` 的调用点及相邻的 `bootMark('notebook bg')`

## 3. 首帧超时兜底（design D4）

- [x] 3.1 在 `addPostFrameCallback` 注册的同时启动一个 10 秒定时器
- [x] 3.2 定时器到期时若首帧回调未触发，强制调用 `windowManager.show()` 并 `debugPrint` 诊断信号
- [x] 3.3 首帧回调触发时取消定时器，避免重复 show

## 4. Refresh 跳过首次冷读（design D3）

- [x] 4.1 修改 `NotebookPage._init()`：`_store.init()` 完成后不立即调 `_refresh()`，改为直接读取 `NoteStore` 单例已加载的数据填充 UI
- [x] 4.2 确认首帧交付后 `_refresh()` 仍可通过焦点桥接（`NotebookFocusBridge`）正常触发，行为不变

## 5. 测试与验证

- [x] 5.1 跑全量测试，确认失败集合与改动前逐字相同
- [ ] 5.2 实机验证：冷启动点「笔记本」，确认窗口几秒后带内容弹出，无黑屏、无空界面
- [ ] 5.3 实机回归：查词浮窗、密码库、运维工具等其他子窗口行为不变
