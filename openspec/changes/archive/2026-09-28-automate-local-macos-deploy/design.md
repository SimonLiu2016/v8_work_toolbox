## Context

现有状态（详见 proposal.md - Why）：

- `scripts/build_installer.sh` 是**分发包**脚本（DMG/ZIP/tar.gz），不是本地替换脚本，不动它
- 部署的正确步骤顺序、每步的失败模式，均由 2026-09 一次黑屏事故复盘固化在 Claude memory 中（signature seal 失效 → Keychain 拒绝 → DEK 文件兜底 → 旧密文解不开）
- `macos/Runner/Resources/mihomo` 在 `.gitignore`，`flutter clean` 会删掉，必须从上一版 bundle 取回
- Xcode 工程没有拷贝 mihomo 的 build phase，它是手工放进 `macos/Runner/Resources/` 的
- mihomo 清理链路：`windowManager.onWindowClose()` → `NetworkProxyService.shutdown()`（`network_proxy_service.dart:243`）→ `MihomoProcessManager.stop()`（`mihomo_process_manager.dart:161`，`proc.kill(sigterm)` 后等 3 秒，超时升级 sigkill）
- 实际部署中曾出现 4 个 PPID=1 的孤儿 mihomo，根因是 `kill -TERM <pid>` 不触发 `onWindowClose()`（窗口事件 ≠ 信号事件）

约束：
- 部署脚本不纳入自动化测试（依赖 `/Applications` 写权限与真机构签），正确性由人工首次执行验证
- `main()` 是黑屏敏感区（任何未捕获异常 = 整个应用黑屏），新增代码必须带守卫

## Goals / Non-Goals

### Goals
- 一条命令完成"清理 → 构建 → 注入 mihomo → 重签名 → 退出旧实例 → 替换 → 校验 → 启动"
- 任一步失败即停，不留下半部署状态
- SIGTERM 触发与 tray quit 相同的清理，消除孤儿 mihomo
- 兜底清理只杀本应用 bundle 路径下的进程，不碰 Clash Verge

### Non-Goals
- 不做 DMG/ZIP 分发包（`build_installer.sh` 已覆盖）
- 不修"增量构建导致 seal 失效"的根因——直接用 `flutter clean` 规避，不碰 Xcode 工程
- 不把 mihomo 纳入 git 或加自动下载——维持"本地 provision"现状
- 不做 CI 集成、不做多机器分发

## Decisions

### D1: `set -euo pipefail` + 显式步骤函数，失败即停

每个步骤一个函数，函数内失败即 `die`。**不**收集错误继续跑——部署到一半的坏状态（bundle 已替换但没签名、或签了名但没启动）比完全没部署更危险。

**为什么不用 `set -e` 裸奔**：`set -e` 在管道和 `if` 条件里行为反直觉。统一的 `die "步骤名"` 明确报出"哪一步死了"，比让 shell 自己猜好。

**替代方案**：`&&` 长链。否决——无法在步骤间插入校验逻辑，错误信息也没有上下文。

### D2: mihomo 来源 = 上一版已部署 bundle，不是源码目录

`cp /Applications/V8WorkToolbox.app/Contents/Resources/mihomo` → 新 bundle。

**为什么不是 `macos/Runner/Resources/mihomo`**：源码目录那份也是手工放的，同样可能被 clean 误删或版本落后。**已部署的那份是"当前正在跑的版本"**，取它注入能保证新 bundle 与线上行为一致。且这份二进制不常变，无版本管理需求。

**兜底**：若 `/Applications` 下没有（首次部署），则回落到源码目录；两边都没有则 `die`，提示用户手动放置。

**哈希校验**：注入后比对源与目标的 md5，确认拷贝完整。

### D3: 签名在注入 mihomo **之后**

顺序固定为：构建 → 注入 mihomo → `codesign --remove-signature` → `codesign -s - --force` → `codesign -v --strict`。

**为什么**：往已签名 bundle 里加文件会破坏 seal（`a sealed resource is missing or invalid`）。反过来先签名再注入 = 必然失败。

**ad-hoc 签名的含义**：`-s -` 是 ad-hoc signature，本地部署够用。这正是 memory 里那条"ad-hoc 签名下 DEK 重启丢失"风险的关联点——本脚本不改变签名策略，只保证每次部署后 seal 自洽。

### D4: 替换用 `rm -rf` + `ditto`，不是 `ditto` 覆盖

`ditto` 是**合并**语义。直接覆盖会在新 bundle 里残留旧 bundle 独有的文件——本次实际踩到过：`kernel_blob.bin`、`vm_snapshot_data`、`isolate_snapshot_data`、`V8WorkToolbox.debug.dylib` 四样漏进了 release bundle，导致 strict 校验失败。

**为什么不用 `mv`**：跨卷（build/ 与 /Applications 同在系统卷，但用户环境可能不同）`mv` 会变成拷贝，不如 `ditto` 明确。`ditto` 保留 resource fork / 扩展属性，对 .app 更安全。

### D5: AOT 快照 = 部署校验的唯一代码身份判据

比对 `Contents/Frameworks/App.framework/Versions/A/App` 的 md5。

**为什么不是 `Contents/MacOS/V8WorkToolbox`**：那是瘦启动器，跨构建可能不变，不能证明代码更新了。Dart AOT 快照才是真正的应用代码。

脚本流程：部署前记录旧哈希 → 部署后取新哈希 → 两者都打印，**若相同则警告但不阻断**（可能是纯资源改动导致的构建，允许人工判断）。

### D6: SIGTERM 监听用 `ProcessSignal.sigterm.watch().listen()`

在 `main()` 的 `WindowServices.initFor(WindowKind.main)` 之后、`runApp()` 之前注册监听：

```dart
ProcessSignal.sigterm.watch().listen((_) async {
  await _gracefulShutdown();
});
```

`_gracefulShutdown()` 复用 `NetworkProxyService.instance.shutdown()`，包 try/catch 守卫（spec: 清理失败不阻止退出），完成后 `exit(0)`。

**为什么不用 `windowManager` 的能力**：它不管进程信号，本次缺陷的根因。

**为什么不用 `PosixSignal` 之外的东西**：Flutter 桌面端 `dart:io` 的信号 API 在 macOS 可用；应用已有 `_MainWindowCloseListener` 调用同一个 `shutdown()`，两条路径收敛到同一清理逻辑，不产生分叉。

**风险**：`exit(0)` 会跳过 Flutter 的 dispose 链。但对本应用，`shutdown()` 只杀子进程，其余状态已落盘（`AppPaths` 下各 store 都是即时持久化），无数据丢失风险。

### D7: 兜底清理精确匹配 bundle 路径

脚本用 `pgrep -f` 匹配完整可执行路径 `V8WorkToolbox.app/Contents/Resources/mihomo`，而非裸 `mihomo`。

**为什么**：本机同时跑着 Clash Verge 的 `verge-mihomo`（PID 观测确认存在），裸匹配会误杀。本次实测：第一次 `pgrep -f mihomo` 返回 5 个，其中有 1 个是 Clash Verge 的。

**触发条件**：仅在优雅退出落地后仍检测到残留时才执行（即"应用没能优雅退出"的兜底），不是无条件每次杀。

## Risks / Trade-offs

- **[脚本误删 /Applications 下的应用]** → `rm -rf` 目标是变量拼出的路径，脚本启动时断言目标路径等于预期的 `/Applications/V8WorkToolbox.app` 前缀，不匹配即 `die`，绝不对任意路径执行 `rm -rf`
- **[构建耗时中断后状态不一致]** → 所有中间产物都在 `build/` 下，`/Applications` 只在最后一步被触碰；失败重跑即可，不需要手动清理
- **[SIGTERM 监听与现有 quit 路径竞态]** → 两条路径都调同一个 `shutdown()`，`MihomoProcessManager.stop()` 首行即 `_process = null`，幂等；重复调用安全
- **[`exit(0)` 跳过 dispose 导致日志未刷盘]** → `AiLogger` 走异步镜像落盘，理论上可能丢最后几条日志。接受：这是诊断日志不是业务数据，且 tray quit 路径本来也不保证刷盘
- **[脚本在 CI / 无 /Applications 写权限的环境失败]** → 明确报错提示"仅限本地 macOS 部署"，不做兼容

## Migration Plan

1. 新增 `scripts/deploy_local.sh`，赋可执行权限
2. 修改 `lib/main.dart` 接入 SIGTERM 监听
3. 跑 `flutter test`（重点 `network_proxy_test.dart`）
4. **人工执行一次** `scripts/deploy_local.sh`，逐项核对脚本输出的校验结果
5. 确认无误后，此前的 memory（手工部署流程）可标记为"已由脚本固化"

**回滚**：脚本删除即回到人工流程；`main.dart` 改动删掉监听即可（`onWindowClose()` 路径本来就是清理主路径，不会因删除而失效）。

## Open Questions

- 是否要在脚本里加 `--skip-clean` 快速模式（跳过 `flutter clean`，用于"只改了 UI 想快速看一眼"）？
  倾向**不加**——clean 是 seal 问题的唯一可靠规避，任何跳过都是给自己挖坑。若后续嫌慢，正确解法是优化构建而不是跳过校验。
- 脚本是否该在成功后自动 `git commit`？倾向**不该**——提交是有语义的动作，混进部署会让 history 出现"构建产物"提交。
