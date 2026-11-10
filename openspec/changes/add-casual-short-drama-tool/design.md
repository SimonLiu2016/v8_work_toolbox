## Context

本工程 `V8WorkToolbox` 拥有完备的「隐私空间」安全架构（PIN 锁、会话锁定监听器 `PrivacySecurityService`、基于 mpv 的 `media_kit` 播放器与私密存储 `PrivateStorageManager`）。
短剧开源项目 `HGhub` 为第三方短剧客户端，其核心在于上游统一网关 `POST /api/edge/request` 信封调用、AES-128-CBC 封面解密及 HLS 视频流播放。
本设计旨在用纯原生 Dart 与 Flutter 将其完整接入隐私空间，提供符合桌面电脑习惯的 16:9 剧场观影体验。

## Goals / Non-Goals

**Goals:**
- 实现纯 Dart 驱动的短剧上游客户端（`HuangguoApiClient`），支持信封请求与自动线路探测。
- 实现纯 Dart AES-128-CBC 封面解密服务与内存/磁盘双级 LRU 缓存，保障海报流畅渲染。
- 实现桌面端 16:9 沉浸式宽屏剧场，视频居中 + 两侧氛围模糊/黑边自适应，提供快捷键支持。
- 实现双栏交互布局：左侧网格探索/搜索/分类/收藏，右侧剧场播放与可折叠选集抽屉。
- 实现纯本地无痕 SQLite 存储（记录收藏列表与断点续播进度），零网络个人数据上报。
- 与 `PrivacySecurityService` 深度打通，锁屏时毫秒级暂停播放并切断音频。
- 提供「下载至私密库」接口，可将选集加入现有的 `DownloadQueueManager`。

**Non-Goals:**
- 不支持上游第三方平台的用户注册/账号登录同步（坚持纯本地无痕/游客隐私模式）。
- 不引入重型 Web 容器或外部 Tauri 子进程，坚持轻量化与零额外打包依赖。

## Decisions

### 1. 纯 Dart 协议封装 vs 引入外部进程
- **决策**：采用纯 Dart `http` / `dio` 实现 API 信封，用 `encrypt` 库解密 AES 封面。
- **理由**：上游协议非常规则（仅 `POST /api/edge/request` 单一信封入口），AES-128-CBC 也是标准算法；纯 Dart 方式避免了启动额外的 Rust/Tauri 进程或 Web 容器，节约 150MB~300MB 内存，启动零延迟。
- **替代方案**：使用 Tauri Sidecar 子进程（弹窗割裂，体积臃肿）或内嵌 WebView（内存开销大且多层通信脆弱）。

### 2. 16:9 桌面宽屏剧场与背景自适应
- **决策**：主视窗统一采用 16:9 桌面宽屏画幅，视频居中呈现，背景层提取当前视频或封面做高斯模糊（`BackdropFilter` / `ImageFilter.blur`）动态渲染。
- **理由**：短剧原生视频流通常为 9:16 竖屏，直接在电脑宽屏拉伸会变形；居中呈现结合两侧弱化动态环境光背景，是目前桌面端视频软件（如 B站、YouTube Shorts 桌面版）的最佳实践。

### 3. 本地私密 SQLite 存储隔离
- **决策**：在 `AppPaths.privatePlayerDir` 下创建独立的 `casual_short_drama.db`，表结构包含 `drama_favorites` 与 `drama_history`。
- **理由**：与常规工作区数据彻底隔离，文件位于加密/受保护的隐私沙箱目录下，用户清空隐私空间或注销时能一并清理。

### 4. 播放器引擎与 PIN 锁硬联动
- **决策**：直接复用 `media_kit` Player 实例，并在 Controller 中注册 `PrivacySecurityService.instance.isUnlockedNotifier` 监听器。
- **理由**：一旦触发锁屏，优先同步调用 `player.pause()` 并静音，防止任何背景音泄露。

## Risks / Trade-offs

- **[上游接口域名或封禁风险]** → 支持动态镜像线路配置与自定义线路输入，内置连通性自检。
- **[短剧 HLS 防盗链与跨域]** → `media_kit` 原生基于 mpv，可以直接在 `Media(url, httpHeaders: {...})` 中注入 `Referer` 与 `User-Agent`，无需额外本地代理转发。
- **[批量封面并发解密耗 CPU]** → 解密后二进制字节做内存 `Map<String, Uint8List>` 缓存，图片解码交给 Flutter 原生引擎，避免重复解密。
