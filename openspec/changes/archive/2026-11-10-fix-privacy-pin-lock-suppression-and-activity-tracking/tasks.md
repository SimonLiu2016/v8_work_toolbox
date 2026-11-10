## 1. 播放抑制器与业务保活接入

- [x] 1.1 在 `CasualShortDramaController` 注册并注销 `PlaybackInhibitor`（`() => isPlaying`）
- [x] 1.2 在 `CasualShortDramaController` 关键交互方法中调用 `recordActivity()`

## 2. 视图层与 AppShell 全局活跃追踪

- [x] 2.1 在 `AppShell` 中当处于 `ActivityViewType.privacy` 时，为主视区注入全量交互 `Listener`
- [x] 2.2 在 `CasualShortDramaPage` 页面层补充交互监听与主动刷新

## 3. 测试与部署验证

- [x] 3.1 编写并运行自动化单元测试，验证短剧播放时抑制自动锁屏及交互刷新逻辑
- [x] 3.2 运行静态代码分析（`flutter analyze`）
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译并替换本机应用
