## 1. 终止死循环孤儿进程与主窗口事件防重入

- [x] 1.1 终止处于 100% CPU 死循环的旧实例进程（PID 20415）
- [x] 1.2 在 `lib/tools/ai_video_studio/ui/studio_shell.dart` 中实现 `_isClosing` 状态自锁与 `windowManager.removeListener(this)` 注销机制，彻底阻断关闭事件递归

## 2. 规范子窗口生命周期调用

- [x] 2.1 改造 `lib/tools/lookup_panel/ui/lookup_window.dart` 中子窗口失焦 `onWindowBlur` 与 `_onClose` 逻辑，杜绝向全局主窗口发送 `windowManager.close()`

## 3. 本地构建部署与能耗验证

- [x] 3.1 执行 `./scripts/deploy_local.sh` 重新构建并替换本机 `/Applications/V8WorkToolbox.app`
- [x] 3.2 启动应用并使用 `ps` / `top` 验证主进程在空闲状态及窗口关闭/失焦后的 CPU 占用率与稳定性
