## 1. VocabStore 数据变更通知

- [x] 1.1 在 `lib/tools/vocab_book/services/vocab_store.dart` 中引入广播流控制器 `StreamController<void>.broadcast()` 并暴露 `Stream<void> get onEntriesChanged`，在写操作（`insertEntry`、`insertFromDictionary`、`deleteEntry`、`deleteEntries`）完成后发射通知
- [x] 1.2 编写或扩充单测 `test/vocab_store_notify_test.dart`，验证新增和删除词条时均会触发 `onEntriesChanged` 事件

## 2. LocalDictionaryBridge 增加 /vocab 端点

- [x] 2.1 在 `lib/services/local_dictionary_bridge.dart` 中添加 `/vocab` 路由处理，严格复用已有的鉴权逻辑（检查 `Authorization` header 或 `secret` query），支持 POST/GET 请求，调用 `VocabStore.instance.existsWord` 判重与 `VocabStore.instance.insertFromDictionary` 写入，返回对应状态 JSON
- [x] 2.2 在 `test/local_dictionary_bridge_test.dart` 中添加 `/vocab` 端点测试用例：未授权拒绝 (401)、有效单词成功新增 (200, status: added)、重复单词跳过 (200, status: already_exists)

## 3. 生词本 UI 订阅实时刷新

- [x] 3.1 在 `lib/tools/vocab_book/ui/vocab_book_page.dart` 的 `initState` 中订阅 `VocabStore.instance.onEntriesChanged`，在收到事件且未处于加载中时调用 `_loadData(silent: true)`，并在 `dispose` 中取消订阅
- [x] 3.2 运行生词本相关测试，确认已有聚焦刷新及签名比对逻辑依然稳健

## 4. 浏览器伴侣扩展支持静默加词

- [x] 4.1 在 `extensions/v8-browser-companion/background.js` 中增加 `addToVocab` 消息处理逻辑，向 `http://127.0.0.1:${BRIDGE_PORT}/vocab` 发送 HTTP 请求并返回结果给前端
- [x] 4.2 在 `extensions/v8-browser-companion/content.js` 中重写「加生词本」点击逻辑：通过 `chrome.runtime.sendMessage({ action: 'addToVocab', ... })` 静默提交，原地更新按钮为「已加入生词本 ✓」或「已在生词本」，彻底移除 `window.location.href = v8toolbox://vocab` 调用

## 5. 校验、部署与实机验收

- [x] 5.1 运行 `flutter analyze` 与全量测试套件，确认零回归
- [x] 5.2 运行 `./scripts/deploy_local.sh` 编译并部署本地桌面应用
- [x] 5.3 重新加载 Chrome 扩展并进行实机交互验收：
  - 浏览器中划词点击悬浮图标，点击「加生词本」：桌面端主窗口**绝不弹出**，小气泡按钮正确显示「已加入生词本 ✓」
  - 桌面端主窗口当前正停留在生词本页面时，浏览器中加词后，生词本列表**实时自动新增展示该词**，无需切走/切回焦点
