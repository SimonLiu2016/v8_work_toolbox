## Why

在磁盘瘦身清理工具中，当用户对 `~/Library/Containers/com.kugou.mac.Music` 等受 macOS 系统沙盒与 TCC（Transparency, Consent, and Control）保护的目录执行「安全移入废纸篓」时，由于应用缺少「完全磁盘访问权限 (Full Disk Access)」，底层移动操作实际已被系统内核拒绝（`Code 513: Operation not permitted`）。

然而，当前 `SystemService.recyclePaths` 存在致命缺陷：
1. 回退 AppleScript 脚本内使用了 `try ... end try`，将 Finder 失败或超时静默吞掉，永远返回退出码 0；
2. 服务层未做任何文件系统物理后置核验（Post-verification），盲目向 UI 汇报成功；
3. UI 误判成功后直接将该条目从列表移除，并向用户提示“已成功移入废纸篓”，造成“虚假删除”的极其严重的体验与信任危机。

必须对废纸篓回收与清理链路进行全面加固，建立真实物理核验机制与精准权限失败提示。

## What Changes

- **真实文件系统后置校验（Post-Verification）**：
  - 在执行任何回收/删除操作后，对目标路径逐一核验物理存在性（`!Directory(p).existsSync() && !File(p).existsSync()`）。
  - 返回详细的结构化执行结果 `RecycleResult`（包含 `successPaths` 与 `failedPaths`），取代含糊易错的单布尔值。
- **清除静默吞错，强化原生与兜底机制**：
  - 移除 AppleScript 内部的静默 `try ... end try` 异常掩盖，确保真实捕获错误与超时；
  - 接入系统原生 `/usr/bin/trash` 与 Cocoa API 协同机制。
- **UI 精准状态联动与权限失败引导**：
  - `SmartDiskSlimmerPage` 仅从界面移除物理确认已不存在的成功项目；
  - 物理依然存在（失败）的条目**严禁从界面移除**；
  - 当检测到失败由于 Full Disk Access 权限受限引起时，精准弹出错误提示，明确指出受限路径并引导前往系统设置开启「完全磁盘访问权限」。

## Capabilities

### Modified Capabilities
- `disk-analyzer`: 强化安全移入废纸篓行为，增加物理后置校验、部分成功/失败精准状态返回与沙盒容器权限受限引导。

## Impact

- **`lib/services/system_service.dart`**：引入 `RecycleResult`，实施真实后置核验，修复 AppleScript 脚本。
- **`lib/tools/slimmer/smart_disk_slimmer_page.dart`**：适配 `RecycleResult`，仅剔除物理已删除条目，对失败条目展示明晰错误弹窗。
- **`test/safe_recycle_hardening_test.dart`**：针对后置核验、部分失败、权限受限等场景编写单元测试。
