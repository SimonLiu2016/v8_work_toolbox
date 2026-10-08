## 1. PATH 搜索与环境变量加固

- [x] 1.1 在 `lib/tools/security_toolbox/services/security_process_runner.dart` 中加入用户目录 `$HOME/.local/bin` 与 `$HOME/bin`，确保 pipx 安装的二进制可被正常发现

## 2. NetExec 专属安装与版本参数修正

- [x] 2.1 在 `lib/tools/security_toolbox/services/security_tool_registry.dart` 中为 `SecurityTool` 增加可选的 `pipxPackage` 字段
- [x] 2.2 将 `netexec` 的 `pipxPackage` 设为 `git+https://github.com/Pennyw0rth/NetExec`，将 `versionArg` 修正为 `--version`
- [x] 2.3 在 `lib/tools/security_toolbox/services/brew_install_service.dart` 的 pipx 分支中使用 `tool.pipxPackage ?? tool.executable` 作为安装参数

## 3. 控制台日志复制与划选支持

- [x] 3.1 在 `lib/tools/security_toolbox/ui/widgets.dart` 的 `LogConsole` 中增加 `SelectionArea` 支持任意划词选区与 Cmd+C 复制
- [x] 3.2 在 `LogConsole` 顶部增加控制台工具栏与“复制全部”按钮，支持一键将日志写入系统剪贴板

## 4. 验证与本地部署

- [x] 4.1 运行单元测试集 `flutter test test/security*` 确保无回归
- [x] 4.2 执行 `flutter analyze lib/tools/security_toolbox/` 确保零告警
- [x] 4.3 执行 `./scripts/deploy_local.sh` 编译并热替换本地 `/Applications/V8WorkToolbox.app`
