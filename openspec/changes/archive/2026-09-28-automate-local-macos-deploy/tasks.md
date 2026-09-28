## 1. 优雅退出（mihomo 子进程清理）

- [x] 1.1 在 `lib/main.dart` 的主窗口 `main()` 路径中，于 `WindowServices.initFor(WindowKind.main)` 之后、`runApp()` 之前注册 `ProcessSignal.sigterm` 监听
- [x] 1.2 新增 `_gracefulShutdown()`：调用 `NetworkProxyService.instance.shutdown()`，整体包 try/catch（清理失败 MUST NOT 阻止退出），完成后 `exit(0)`
- [x] 1.3 确认 `_MainWindowCloseListener.onWindowClose()` 与 SIGTERM 两条路径都收敛到同一个 `shutdown()`，不产生分叉实现
- [x] 1.4 新增测试覆盖 SIGTERM 监听路径的清理调用（不真实发信号，在测试中直接调用注册的清理入口或断言其可注入性）
- [x] 1.5 运行 `flutter test test/network_proxy_test.dart test/mcp_assistant_test.dart` 确认无回归

> 落地说明：清理逻辑收敛为单一 `runShutdownCleanup({bool forTest})`，SIGTERM 监听与测试入口共用。测试首次运行时 3 个用例全部 `did not complete`——因为 `exit()` 在测试进程里会真的终止 flutter_tester（报 `Shell subprocess ended cleanly. Did main() call exit()`）。故 `forTest: true` 时改调可注入的 `exitOverride`，生产路径仍走真实 `exit(0)`。

## 2. 部署脚本

- [x] 2.1 新增 `scripts/deploy_local.sh`，`set -euo pipefail`，定义统一 `die` 与步骤函数风格
- [x] 2.2 步骤 `preflight`：校验在 macOS、`flutter` 可用、并断言部署目标路径以 `/Applications/V8WorkToolbox.app` 为前缀，不匹配即 `die`
- [x] 2.3 步骤 `build`：`flutter clean` → `flutter build macos --release`，失败即停且不触碰 `/Applications`
- [x] 2.4 步骤 `inject_mihomo`：优先从 `/Applications/V8WorkToolbox.app/Contents/Resources/mihomo` 取，缺失则回落 `macos/Runner/Resources/mihomo`，两者都无则 `die`；拷贝后比对 md5
- [x] 2.5 步骤 `resign`：`codesign --remove-signature` → `codesign -s - --force` → `codesign -v --strict`，strict 不过即停
- [x] 2.6 步骤 `stop_running`：SIGTERM 优雅退出；宽限后仅对仍存活且 PID 属于 `V8WorkToolbox.app/Contents/MacOS` 的实例升级处理
- [x] 2.7 步骤 `cleanup_orphans`（兜底）：仅在检测到残留时执行，`pgrep -f` 精确匹配 `V8WorkToolbox.app/Contents/Resources/mihomo` 完整路径，不得匹配其他应用的同类名进程
- [x] 2.8 步骤 `replace`：记录旧 AOT 快照 md5 → `rm -rf /Applications/V8WorkToolbox.app` → `ditto` 新 bundle 到 `/Applications`
- [x] 2.9 步骤 `verify`：`codesign -v --strict` 部署后 bundle；取新 AOT 快照 md5 并与旧值一并输出，相同则警告但不阻断
- [x] 2.10 步骤 `launch`：`open -a` 启动，等待固定时长确认进程存活，未存活则 `die` 并保留已部署 bundle 便于人工排查
- [x] 2.11 `chmod +x scripts/deploy_local.sh`，并在 `scripts/README.md` 补充用途说明（与 `build_installer.sh` 的分工）

> 落地说明：保留了 `--skip-clean` 参数但脚本头部给出明确警告（这是 design 的「不加快速模式」决定的执行方式——不鼓励、不隐藏、仍可用）。构建日志落 `/tmp/deploy_build.log`，失败时打印尾部 30 行而非全量刷屏。

## 3. 验证

- [x] 3.1 人工执行 `scripts/deploy_local.sh` 一次，逐项核对脚本输出的构建、签名、AOT 哈希、进程存活校验结果
- [x] 3.2 人工验证 SIGTERM 优雅退出：启动应用与 mihomo 后`kill -TERM` 主进程，确认无 PPID=1 的 `Resources/mihomo` 残留
- [x] 3.3 运行全量 `flutter test`，与既有基线（773 passed / 3 skipped / 15 已知历史失败）对比确认无新增失败
- [x] 3.4 运行 `openspec validate automate-local-macos-deploy --type change`

> 验证说明：
> - **3.1** 脚本 13:27:48 起跑、13:32:54 结束。9 个步骤全部通过；AOT 快照
>   `ad567bdd…` → `9622f62b…`（SIGTERM 改动确实进了 Dart 代码）；strict
>   签名校验通过；应用启动存活。
> - **3.2** 首次部署时 `cleanup_orphans` 报了一次发现残留 mihomo（PID 20222）——
>   这是**旧版本**（未含 SIGTERM 修复）的应用被 TERM 后留下的，兜底清理按预期
>   生效。新版本实测：`kill -TERM` 主进程 5 秒后 main=0 / mihomo=0、
>   7890 端口释放、全系统无 `Resources/mihomo` 残留。**优雅退出确认生效。**
> - **3.3** 全量 `flutter test` 结果 `778 passed / 3 skipped / 13 failed`。
>   较上一轮基线（773/3/15）：passed +5（新增 3 个 SIGTERM 用例 + 2 个
>   flaky 用例本轮通过），failed −2（mcp_assistant 的 testConnection 与
>   evernote_import 各 1 条本轮 flaky 通过）。**失败集仍全部落在既有的
>   notebook 表格/编辑器交互与 AiLogger 落盘两组历史红灯内，无新增失败。**
> - **3.4** `openspec validate` 通过。
