## Why

在浏览器中使用划词气泡点击「加生词本」时，当前存在两大体验问题：
1. **弹出主窗体打断阅读**：点击「加生词本」会触发 `window.location.href = 'v8toolbox://vocab?text=...'` 深链，macOS LaunchServices 在分发 URL Scheme 时会强制激活应用（Activate）并将主窗口置顶前台，强行打断用户的网页阅读；
2. **生词本列表不实时刷新**：主窗口若已处于生词本页面，新入库的单词无法实时显示在列表中，必须将系统焦点切换到其他软件再切回当前软件（依赖 `onWindowFocus`）后新词才出现。

浏览器扩展早已拥有成熟且静默的本地 HTTP 词典桥（`LocalDictionaryBridge`，`127.0.0.1:8797`），完全不应走系统级 URL Scheme 唤起；同时 `VocabStore` 应具备数据变更通知能力，驱动 UI 实时就地刷新。

## What Changes

- **浏览器伴侣改走本地 HTTP 桥静默加词**：
  - 扩展 `content.js` 点击「加生词本」不再使用 `v8toolbox://vocab` 深链导航，改为向 `background.js` 发送 `addToVocab` 消息。
  - `background.js` 通过 HTTP `POST /vocab` 访问本地桥（携带鉴权密钥与单词、释义等数据），静默写入生词本。
  - 气泡卡片按钮原地更新为「已加入生词本 ✓」（若已存在则显示「已在生词本」），并在 1.2 秒后自动淡出关闭，全程零弹窗、零焦点切换。
- **本地词典桥（`local-dictionary-bridge`）扩充 `/vocab` 端点**：
  - 增加 `POST /vocab`（或 `GET /vocab`），校验密钥鉴权后调用 `VocabStore.instance.insertFromDictionary`，返回 `{ ok: true, status: 'added' | 'already_exists' }`。
- **`VocabStore` 引入数据变更广播与生词本实时刷新**：
  - `VocabStore` 提供数据变更通知（`onEntriesChanged` / `ChangeNotifier`），在插入、删除或更新生词条目后广播变更。
  - `VocabBookPage` 订阅该变更通知，在主窗口打开生词本时立即静默重新加载列表（`_loadData(silent: true)`），无需切走窗口再切回。

## Capabilities

### New Capabilities
- `vocab-book-live-update`: `VocabStore` 提供数据写入/变更广播，主窗体生词本页面响应变更并实时无感刷新列表，无需依赖窗口失去/重获焦点。

### Modified Capabilities
- `local-dictionary-bridge`: 扩展本地桥能力，支持安全的 `/vocab` 生词写入接口，免受操作系统 URL Scheme 干扰。
- `browser-companion-extension`: 浏览器原地气泡「加生词本」动作改为经由本地桥静默提交，原地更新按钮视觉状态，不呼起桌面端窗口。

## Impact

- **浏览器扩展**：`extensions/v8-browser-companion/content.js`、`extensions/v8-browser-companion/background.js`。修改后需重载 Chrome 扩展。
- **桌面端网络服务**：`lib/services/local_dictionary_bridge.dart` 新增 `/vocab` 处理分支，响应 JSON 结果。
- **桌面端存储与 UI**：
  - `lib/tools/vocab_book/services/vocab_store.dart` 增加数据变更事件通知。
  - `lib/tools/vocab_book/ui/vocab_book_page.dart` 监听变更通知并静默刷新列表。
- **深链兼容性**：保留现有的 `v8toolbox://vocab` 兜底兼容，但不推荐作为扩展首选路径。
