## 1. 基础服务与数据层实现

- [x] 1.1 创建数据模型 `DramaCard`, `DramaDetail`, `DramaEpisode`, `DramaPlayInfo` 及 `LineState`
- [x] 1.2 实现 `HuangguoApiClient`，支持 `POST /api/edge/request` 信封调用、多镜像线路探测与持久化
- [x] 1.3 实现 `DramaCoverDecryptor`，基于 AES-128-CBC 解密封面密文并提供内存/磁盘双级缓存
- [x] 1.4 实现 `CasualShortDramaStore` 本地私密 SQLite 数据库，管理用户收藏与观看历史进度

## 2. 业务控制器与安全联动

- [x] 2.1 实现 `CasualShortDramaController`，驱动播放列表加载、选集切换、自动连播与进度记录
- [x] 2.2 接入 `media_kit` 播放引擎与 `PrivacySecurityService`，实现隐私空间锁定时毫秒级自动暂停与切断音频
- [x] 2.3 对接 `DownloadQueueManager`，支持单集或批量将短剧加入私密下载队列并离线播放

## 3. 界面呈现与交互实现

- [x] 3.1 实现桌面端 16:9 沉浸式宽屏剧场组件 `DramaTheaterSurface`，视频居中搭配环境光模糊背景
- [x] 3.2 实现选集抽屉 `DramaEpisodeDrawer`，支持分段集数切换与当前播放高亮标记
- [x] 3.3 实现左侧短剧网格探索栏（推荐/榜单/分类标签/搜索/我的收藏）
- [x] 3.4 支持桌面端标准键盘快捷键（空格播放/暂停、左右快进/退、上下切集、M 静音、F 全屏）

## 4. 工具注册与系统集成

- [x] 4.1 在 `lib/tools/registry.dart` 与 `tool_definition.dart` 中注册「随心短剧」（`casual_short_drama`）
- [x] 4.2 接入隐私空间导航与主视图路由，确保锁定时完全隐藏、解锁后方可访问

## 5. 测试验证与本地部署

- [x] 5.1 编写 `HuangguoApiClient` 与 `DramaCoverDecryptor` 单元测试，验证信封拼装与 AES 封面解密正确性
- [x] 5.2 编写 `CasualShortDramaStore` 单元测试，验证无痕游客收藏与播放进度落盘
- [x] 5.3 运行 `flutter test` 与静态代码分析，确保零告警
