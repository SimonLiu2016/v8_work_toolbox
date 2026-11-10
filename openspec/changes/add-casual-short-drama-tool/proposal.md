## Why

短剧作为一种极受欢迎的新兴流媒体娱乐形态，具有单集时间短、剧情紧凑等特点。开源项目 [Minireel/HGhub](https://github.com/Minireel/HGhub) 提供了优秀的短剧第三方客户端方案。在 V8WorkToolbox 体系中，用户希望在工作间隙能够在桌面端大屏上快速浏览与观看短剧，同时要求高度注重个人隐私保护（具备 PIN 码防护、零个人账号痕迹、无痕游客浏览、离线下载保存至私密库，以及在锁定/切换时瞬间静音防泄露）。

将短剧能力以纯原生 Flutter 模块（「随心短剧」）的形式内置于已有的「隐私空间」中，既能充分享受原生桌面宽屏（16:9）与 `media_kit` 硬件加速播放的高流畅度，又能与现有的 PIN 码安全锁及私密下载存储管理器深度打通，提供安全、优雅且无额外进程开销的随心观剧体验。

## What Changes

- **新增「随心短剧」隐私工具注册**：在 `lib/tools/registry.dart` 的 `ToolCategory.privacy` 分类下注册「随心短剧」（`casual_short_drama`），仅在用户成功解锁隐私空间后可见。
- **构建纯 Dart 驱动的上游 API 与流媒体解密层**：
  - 实现 `HuangguoApiClient`，封装上游统一网关 `POST /api/edge/request` 信封协议（支持 feed、rank、category、search、detail、play 接口）。
  - 内置基于 AES-128-CBC 的封面密文解密（静态密钥 Key: `f5d965df75336270`, IV: `97b60394abc2fbe1`），结合本地内存与磁盘 LRU 缓存，实现秒级海报渲染。
  - 支持多镜像线路自动与手动探测测速（默认 `https://huangguoai.com`）。
- **纯本地无痕 / 游客模式与私密隔离存储**：
  - 无需注册登录，零个人信息上传，保护用户隐私。
  - 收藏夹与播放进度记录落盘至独立的 SQLite 私密隔离数据库中。
- **16:9 大屏桌面沉浸式剧场与播放控制台**：
  - 专为桌面端电脑优化的 16:9 宽屏视窗，视频居中自适应，两侧采用高斯模糊背景或沉浸纯黑底色填充。
  - 左右并列交互布局：左侧为多维度探索（推荐、热榜、分类标签、搜索框、收藏夹），右侧为主播放视窗与折叠选集抽屉。
  - 完善的桌面键盘快捷键（空格暂停/播放、左右快进/退 5 秒、上下切集、F 全屏切换、M 静音）。
- **隐私安全锁联动**：
  - 监听 `PrivacySecurityService`：当隐私空间因闲置超时或用户手动锁定时，立即暂停播放器并彻底切断音频输出。
- **私密下载与媒体库互通**：
  - 提供「下载至私密库」功能，支持单集或选集加入 `DownloadQueueManager` 下载至本地私密文件夹，支持无网离线观看。

## Capabilities

### New Capabilities
- `casual-short-drama`: 涵盖随心短剧的 API 聚合、封面 AES 解密、16:9 桌面宽屏播放器、沉浸选集抽屉、纯本地无痕收藏与播放记录、离线下载至私密库及 PIN 锁安全联动全套能力。

### Modified Capabilities
（无需求级行为变更，现有 `privacy-space` 与 `private-media-player` 规范保持不变）

## Impact

- **代码结构**：新增 `lib/tools/casual_short_drama/` 模块，包含 `services/` (API、解密、Repository、控制器) 与 `ui/` (主工作台、播放器、选集抽屉、搜索与分类栏)。
- **工具注册**：更新 `lib/tools/registry.dart` 与 `lib/tools/tool_definition.dart`。
- **依赖库**：复用现有的 `media_kit`, `media_kit_video`, `encrypt`, `sqflite`/`sqlite3`，无需引入额外依赖。
- **系统资源**：纯 Flutter + mpv 运行，无额外 Web 容器进程开销。
