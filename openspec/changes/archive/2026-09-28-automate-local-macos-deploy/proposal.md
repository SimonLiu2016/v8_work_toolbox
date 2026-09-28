## Why

本地应用的"重新构建并替换"目前是一套需要人工逐步执行的操作序列：`flutter clean` → `flutter build macos --release` → 从旧 bundle 拷 mihomo 进新 bundle → 重新 ad-hoc 签名 → 杀掉所有 mihomo 残留 → `rm -rf` 旧 bundle 后 `ditto` 替换 → `codesign --strict` 校验 → 启动采样。这条链条长约 10 步，每步都有已知的、由 memory 记录过的失败模式（签名 seal 失效导致 Keychain 拒绝、`ditto` 合并残留 debug 构建产物），且此前每次都由人工引导执行，无法保证步骤不遗漏。

同时发现一个代码缺陷：主进程被 SIGTERM 时 mihomo 子进程不会被清理。`MihomoProcessManager` 的清理挂在 `windowManager` 的 `onWindowClose()` 上，而那是**窗口关闭**事件不是进程信号事件，导致每次非正常退出都会留下 PPID=1 的孤儿进程（实测已累积 4 个），并持续占用 `127.0.0.1:7890`。

## What Changes

- **新增一键本地部署脚本** `scripts/deploy_local.sh`，按固定顺序完成：构建前清理 → release 构建 → 注入 mihomo 二进制 → 重新 ad-hoc 签名 → 优雅退出旧实例 → 部署后校验 → 启动应用。任何一步失败即整体中止，不留下半部署状态。
- **新增优雅退出路径**：主窗口监听 `SIGTERM`，收到信号后执行与 `onWindowClose()` 相同的清理（停止 mihomo 子进程），然后退出进程。修复孤儿 mihomo 累积问题。
- **部署脚本保留兜底清理**：优雅退出落地后，脚本对"仍存活的 mihomo 残留"只在应用未能优雅退出时才清理，且精确匹配本应用的 bundle 路径，避免误杀 Clash Verge 的 `verge-mihomo`。

## Capabilities

### New Capabilities

- `local-deploy-automation`：本地 macOS 构建与部署的自动化契约，覆盖一次性脚本的成功路径、失败即停语义、以及产物校验要求。该能力同时约束 mihomo 子进程在应用退出时的清理行为。

### Modified Capabilities

- `workspace-navigation`：应用退出语义扩展——除菜单栏 quit 与窗口关闭外，新增进程级 SIGTERM 触发的清理路径。

> 说明：本 change 对最终用户功能零影响。两条 spec 分别固化"部署流程的可重复性"与"退出时子进程清理"这两个此前只存在于运维惯例中的行为，防止流程回退到人工引导。

## Impact

### Affected Code
- `scripts/deploy_local.sh`（新增）
- `lib/main.dart` — 新增 SIGTERM 监听，接入既有 `NetworkProxyService.shutdown()`
- `lib/tools/network_proxy/services/` — 无需改动；复用现有 `shutdown()` / `stop()`

### Affected APIs / Dependencies
- `NetworkProxyService.shutdown()` 与 `MihomoProcessManager.stop()` 已存在，本 change 只新增一个调用入口，不改其签名
- `flutter clean` 会删除 `macos/Runner/Resources/mihomo`（该文件在 `.gitignore`），脚本必须从上一版已部署的 bundle 取出并注入

### Test Impact
- 新增测试覆盖 SIGTERM 监听路径的清理调用（不真实发信号，改为在测试中触发监听器）
- 部署脚本不纳入自动化测试（osascript/quarts 与 /Applications 权限不适合 CI），其正确性由人工首次执行验证
