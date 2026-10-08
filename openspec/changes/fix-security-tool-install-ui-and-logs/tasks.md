## 1. 子进程环境变量加固

- [x] 1.1 在 `lib/tools/security_toolbox/services/security_process_runner.dart` 的 `processEnvironment` 中注入 `HOMEBREW_NO_AUTO_UPDATE`、`NONINTERACTIVE` 与 `HOMEBREW_NO_INSTALL_CLEANUP`

## 2. 日志流打通与逐项就绪回调

- [x] 2.1 在 `lib/tools/security_toolbox/services/brew_install_service.dart` 的 `install` 方法中添加可选 `void Function(String)? onLog` 参数，实时转发命令与每行 stdout/stderr
- [x] 2.2 在 `BrewInstallService.installAllMissing` 中添加 `onLog` 参数及每项完成回调，支持逐个工具即时刷新

## 3. 界面状态机与实时控制台集成

- [x] 3.1 在 `lib/tools/security_toolbox/ui/tool_status_panel.dart` 中增加 `_installingToolId` 与 `_installingAll` 状态变量与防重复点击控制
- [x] 3.2 改造工具条目中的操作按钮，在对应工具安装或更新期间呈现加载动画与“安装中…”/“更新中…”文案
- [x] 3.3 改造顶部“一键安装”按钮，在批量执行时呈现加载动画与“安装全部中…”文案
- [x] 3.4 在 `ToolStatusPanel` 底部集成 `LogConsole`，展示实时安装日志与操作历史
- [x] 3.5 在批量安装时逐个记录进度日志（如 `[1/N] 正在安装 xxx...`）并实时刷新工具探测状态

## 4. 验证与回归测试

- [x] 4.1 运行全量单元测试与安全工具测试集确认无回归
- [x] 4.2 执行 `flutter analyze lib/tools/security_toolbox/` 确保零告警
