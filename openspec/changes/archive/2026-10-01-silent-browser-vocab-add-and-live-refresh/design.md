## Context

当前从浏览器划词气泡点击「加生词本」会通过 `window.location.href = 'v8toolbox://vocab?text=...'` 呼起操作系统 URL Scheme，触发 macOS LaunchServices 将桌面端主窗口推至前台。而在桌面端内部，`VocabStore` 写入 SQLite 后缺少事件通知，导致已打开的 `VocabBookPage` 必须等待窗口失焦并重新聚焦后才刷新列表。

相关动机与需求参见 `proposal.md` 与 specs。

## Goals / Non-Goals

**Goals:**
- 浏览器原地气泡点击「加生词本」完全在后台完成（走本地 HTTP 桥），保证 100% 不拉起桌面端主窗口、不抢夺系统焦点。
- 气泡内的「加生词本」按钮根据响应就地更新为「已加入生词本 ✓」或「已在生词本」，平滑淡出。
- `VocabStore` 引入进程内数据变更通知流，驱动处于活动状态的 `VocabBookPage` 就地静默刷新，即时显示新增词条。
- 保持既有 `v8toolbox://vocab` 深链及 `onWindowFocus` 聚焦刷新的向后兼容性。

**Non-Goals:**
- 不重写或移除 `onWindowFocus`：聚焦刷新对于多进程/独立子窗口（如 lookup_window）写库后的主窗口同步仍是必要的安全网。
- 不修改除词典与生词本之外的其他桥接端点（笔记保存等）。

## Decisions

### Decision 1: 本地桥新增 `/vocab` 端点，取代系统 URL Scheme

- **选择**：在 `LocalDictionaryBridge`（监听 `127.0.0.1:8797`）中新增 `/vocab` 路由。支持 `POST`（带 JSON 请求体：`word`、`phonetic`、`definitions`、`examples` 等）以及简单 `GET /vocab?word=...`。
- **鉴权**：复用现有的恒定时间常量比较 `_constantTimeEquals(supplied, expected)`，与 `/dictionary` 一致。
- **返回结构**：
  - 成功新增：`{ "ok": true, "status": "added", "word": word }`（HTTP 200）
  - 已存在：`{ "ok": true, "status": "already_exists", "word": word }`（HTTP 200）
  - 鉴权失败：`{ "ok": false, "reason": "unauthorized" }`（HTTP 401）
  - 单词无效：`{ "ok": false, "reason": "bad_word" }`（HTTP 400）
- **权衡与备选**：曾考虑在原生 Swift 层收到 `v8toolbox://vocab` 时强行隐藏窗口。但 macOS LaunchServices 在分发 URL Scheme 时是在进程外强行将应用设为 active，在应用内试图将其压回后台会产生明显的屏幕闪烁和焦点抢夺竞态。HTTP 本地回环请求天生是后台网络 IO，从根源上杜绝了窗口管理器介入。

### Decision 2: 浏览器扩展内由 Service Worker 转发加词请求

- **选择**：
  - `content.js` 监听到 `#v8-btn-vocab` 点击后，向 background service worker 发送 `{ action: 'addToVocab', word, ... }`。
  - `background.js` 复用与 `fetchDictionary` 相同的 `BRIDGE_PORT`、`BRIDGE_SECRET` 和超时配置，向 `http://127.0.0.1:${BRIDGE_PORT}/vocab` 发起 `fetch` 请求。
  - `content.js` 收到响应后：
    - `added`：按钮变为 `已加入生词本 ✓`
    - `already_exists`：按钮变为 `已在生词本`
    - `bridge_offline`：按钮显示 `桌面端未启动`
    - 其它错误：按钮显示 `添加失败`
    - 1.2 秒后平滑调用 `dismissBubble()`。
- **权衡与备选**：不直接在 `content.js` 发 `fetch`，是为了保持 host 权限收敛在 background.js，且不破坏网页 CSP 环境。

### Decision 3: `VocabStore` 广播变更与 `VocabBookPage` 订阅刷新

- **选择**：
  - `VocabStore` 维护一个广播 `StreamController<void> _changeController = StreamController<void>.broadcast()`，暴露 `Stream<void> get onEntriesChanged`。
  - 在 `insertEntry`、`insertFromDictionary`、`deleteEntry`、`deleteEntries` 执行完成后调用 `_changeController.add(null)`。
  - `VocabBookPage` 在 `initState` 中注册监听 `_storeSubscription = _store.onEntriesChanged.listen((_) => _loadData(silent: true))`，在 `dispose` 中取消订阅。
- **效果**：
  - 本地桥写库后，立即触发通知，前台如果正开着生词本，列表立即自动加载新词，`vocabListChanged` 比对通过后自动更新 `_entries`，零卡顿零重绘闪烁。
  - 如果用户不在生词本页面，页面下次进入时由 `initState` 全量加载；若从后台切回，由 `onWindowFocus` 兜底。

## Risks / Trade-offs

- **[Risk] 桌面端未运行时浏览器点击「加生词本」** → Mitigation: `background.js` 识别 `bridge_offline`，气泡按钮显示「桌面端未启动」提示，避免静默失败，也不盲目唤起系统报错。
- **[Risk] 频繁加词导致列表抖动** → Mitigation: 现有的 `_loadData(silent: true)` 已经具备 `vocabListChanged` 签名比对与选中项保持逻辑，只有确实展示内容不同时才会 `setState`，保证无白闪。
- **[Risk] 旧版扩展或外部工具仍然使用 `v8toolbox://vocab`** → Mitigation: `main.dart` 中的 `_addWordToVocabFromBridge` 保留，它调用的也是 `VocabStore.instance.insertFromDictionary`，同样会触发广播，保证双向兼容。

## Migration Plan

1. 桌面端 `VocabStore` 接入变更通知，更新单元测试。
2. 桌面端 `LocalDictionaryBridge` 接入 `/vocab` 路由及测试。
3. 桌面端 `VocabBookPage` 接入变更订阅。
4. 浏览器扩展 `content.js` 与 `background.js` 迁移至本地桥请求。
5. 运行 `./scripts/deploy_local.sh` 部署并重载 Chrome 扩展进行实机验收。
