## Why

浏览器伴侣扩展的划词气泡一直是「查询失败」。上一轮改动（`add-global-theme-and-fix-companion-lookup`）诊断为主机页 CSP/CORS 拦截，把请求从 `content.js` 搬到 `background.js` 的 service worker，并补了 `host_permissions`；方向符合 Chrome 官方对 MV3 的约束，但漏了一件事：**服务端那头认不认这个 Origin**。

实测（带扩展 Origin 的请求形状）：

| 请求 | 结果 |
| --- | --- |
| `dict.youdao.com/jsonapi` + `Origin: chrome-extension://…` | **403 `Invalid CORS request`**（0.4s） |
| `api.dictionaryapi.dev` + 同一 Origin | **Cloudflare 522**（约 20s） |
| 桌面应用 `http.get`（**不带 Origin**） | **200 + `ec` 词条**（0.3s） |

`host_permissions` 只让 Chrome 跳过浏览器这一侧的 CORS 检查，**不会把 `Origin` 请求头抹掉**。有道据此拒绝。因此从 service worker 直连有道 jsonapi 这条路是死的，与代码怎么写无关——这也是为什么桌面端同样查这个词却一直正常：它走 `v8toolbox://` 深度链接 → `AppDelegate` → `MethodChannel` → `YoudaoService`，压根不带 `Origin`。

叠加问题：Chrome 加载的仍是 `v1.0.0` 扩展（`service_worker_registration_info.version`，安装于 09-28 08:30），而磁盘代码在当天 19:06 才改写为 1.1.0。未打包扩展不会自动重载，旧 SW 没有 `runtime.onMessage` 监听器，`sendMessage` 直接落到 `chrome.runtime.lastError`，于是气泡停在 `content.js:339` 的「查询失败」分支。

## What Changes

- **新增回环词典桥 `local-dictionary-bridge`**：桌面应用在 `127.0.0.1` 上开一个本地 HTTP 端点，把词典查询代理给既有的 `YoudaoService`。ACAO 由我们自己设置，不存在第三方 CORS 变数；词典实现也只保留桌面应用一处，扩展退化成壳。
- **扩展改为查本地桥**：`background.js` 的 `fetchDictionary` 先打回环端点；桥不在线（桌面应用未启动）时**立即**回落，不再用 20s 的超时去赌一个 522。
- **修掉 service worker 的时间炸弹**：`background.js` 两个 `await fetch` 都没有 `AbortSignal` 超时。有道 403 后落到 FreeDict 实测 20s 才回，而 MV3 的规则是 fetch 响应超过 30 秒即杀掉 worker——那一次 `sendResponse` 永远发不出去，气泡卡死在「查询中…」。
- **区分两种失败**：`fetchDictionary` 失败时不再复用成功的响应形状。`content.js` 现在把「网络/桥不通」和「词典未收录该词条」渲染成同一套 UX，文案会骗人。
- **修复扩展重载问题**：把「改动 `extensions/` 后必须去 `chrome://extensions` 重载」写进本地部署脚本与 README，使 `scripts/deploy_local.sh` 之后这一步不再靠记忆。

## Capabilities

### New Capabilities

- `local-dictionary-bridge`: 桌面应用暴露的本地回环词典服务——绑定 `127.0.0.1`、单端口、带共享密钥、由宿主应用生命周期管理，供本地受信客户端（浏览器伴侣扩展）查询词典。

### Modified Capabilities

- `browser-companion-extension`: 「Service worker delegated dictionary lookups」的要求从「直连外部词典 API」改为「经由本地词典桥解析」；补上请求超时、离线回落与失败态区分的场景。

## Impact

- **Flutter 层**：新增 `lib/services/local_dictionary_bridge.dart`（HttpServer + 路由 + 密钥校验）；`lib/main.dart` 主窗口 init 链上启动、`runShutdownCleanup` 里关闭；端口与密钥持久化进 `SettingsStore`（沿用 `themeMode` 的模式）。
- **浏览器伴侣**：`background.js` 的 `fetchDictionary` 改打回环端点并加 `AbortController`；`manifest.json` 的 `host_permissions` 从外部词典域名改为回环地址，版本号 1.2.0（触发重载）。
- **运维**：`scripts/deploy_local.sh` 或 README 增加「重载扩展」提示。
- **依赖**：无新增第三方依赖，本地 HTTP 用 Dart 自带 `dart:io` 的 `HttpServer`。
- **不变**：`v8toolbox://` 深度链接两条链路（`lookup` / `savenote`）与 `YoudaoService` 的解析逻辑均不动。
