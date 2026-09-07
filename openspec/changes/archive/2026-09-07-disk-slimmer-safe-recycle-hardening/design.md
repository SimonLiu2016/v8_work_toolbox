## Context

在 macOS 现代系统架构下，`~/Library/Containers` 中的沙盒应用容器受到系统守护进程 `containermanagerd` 及 TCC 的强保护。普通进程若未被赋予「完全磁盘访问权限 (Full Disk Access)」，在对其执行删除或移动到废纸篓时会遭遇 `NSCocoaErrorDomain Code 513 (Operation not permitted)` 阻断。

先前的实现中，`SystemService.recyclePaths` 将 AppleScript 封装在 `try ... end try` 中吞没了所有错误，且无任何物理后置核验，向 UI 误报成功，导致用户看到假象。

## Goals / Non-Goals

**Goals:**
- 将单一布尔返回值重构为结构化 `RecycleResult`（包含 `successPaths`、`failedPaths`、`errorMessage`）。
- 实施绝对物理后置核验：在调用系统回收后，通过 `Directory(p).existsSync()` 和 `File(p).existsSync()` 逐个检验路径，未物理消失的视为失败。
- 修复 AppleScript 静默吞错，并引入 `/usr/bin/trash` 强化回收能力。
- 在 `SmartDiskSlimmerPage` 中根据真实核验结果联动 UI：仅剔除物理已移除的条目，对失败条目予以保留并精准弹窗提示授予「完全磁盘访问权限」。

**Non-Goals:**
- 越权绕过 macOS SIP 或 TCC 机制（操作系统底线安全规则不可绕过）。
- 采用不可逆的 `rm -rf` 强制销毁（必须保持安全可撤回移入废纸篓原则）。

## Decisions

### 决策 1: 引入 `RecycleResult` 与物理双重核验
- **选择**: 无论原生 Channel、系统 `trash` 还是 AppleScript 执行结果如何，最终以 Dart 对本地文件系统的实际检查为准：
  ```dart
  final success = <String>[];
  final failed = <String>[];
  for (final path in paths) {
    if (!Directory(path).existsSync() && !File(path).existsSync()) {
      success.add(path);
    } else {
      failed.add(path);
    }
  }
  ```
- **理由**: 文件系统真实状态是唯一的不可伪造的真理，彻底杜绝任何原因导致的“虚假成功”。

### 决策 2: 移除 AppleScript 中的静默吞错
- **选择**: 移除 `try ... end try`，改用带有超时控制的脚本执行；若抛出异常直接由外层捕获并记录错误原因。

### 决策 3: UI 区分全部成功、部分成功与全部失败
- **选择**:
  - 全部成功：Toast 提示释放空间；
  - 部分/全部失败：保留未删除条目在列表上，弹出 Dialog 或醒目 SnackBar 提示原因，若涉及 `Containers` 则明确告知需要“完全磁盘访问权限”，并提供打开系统设置或在访达中定位的指引。

## Risks / Trade-offs

- **[风险] `existsSync()` 在超大目录或网络驱动器上可能存在极短的缓存延迟**
  - *缓解措施*: 在调用系统回收与执行核验之间加入微量等待（如 100ms），确保操作系统文件系统元数据更新到位。
