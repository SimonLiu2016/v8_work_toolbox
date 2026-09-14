# Design: Administrator-Elevated Disk Cleaning and Pre-scan Ownership Detection

## Context

See `proposal.md` for motivation.
Certain orphaned directories (e.g. `/Users/simon/Library/Application Support/jsDesignAgent`) were created with root ownership (`drwxr-xr-x root:staff`). Normal user processes cannot move root-owned files to macOS Trash without administrator privileges. The app currently misdiagnoses all trash failures as lacking TCC "Full Disk Access", misdirecting users.

## Goals / Non-Goals

**Goals:**
- Identify root-owned candidate items during disk scanning and mark them with `requiresAdmin = true`.
- Display a visually distinct "需管理员权限" badge and default them to unselected (caution rating).
- Differentiate between TCC sandboxing restrictions, root POSIX ownership, and file busy locks in trash failure reporting.
- Provide a secure, in-app administrator elevation flow via AppleScript (`do shell script with administrator privileges`) allowing one-click Touch ID / password cleaning.
- Enforce strict security boundaries to prevent path traversal or modification of system files.

**Non-Goals:**
- Running the entire V8WorkToolbox application as root.
- Installing permanent background launch daemons (`SMJobBless` or helper tools).
- Modifying system files outside user Library or temporary directories.

## Decisions

### Decision 1: Pre-scan privilege detection using lightweight file stat inspection
- **Choice**: During scanning in `app_orphan_detector.dart` and `disk_scanner_service.dart`, verify directory ownership. On macOS, inspect directory UID or user write permissions. Items with UID 0 (root) or unwritable by the current user are flagged `requiresAdmin = true`.
- **Rationale**: Inspection is performed on only candidate items (dozens to a few hundred), adding negligible latency (<50ms).

### Decision 2: UI Badging & Safety Rating
- **Choice**: Items with `requiresAdmin == true` display a lock icon with `需管理员权限` badge. Their `safety` defaults to `SafetyRating.caution` and `isSelected` defaults to `false`.
- **Rationale**: Prevents users from having their routine "one-click clean" interrupted by unexpected system password prompts unless they deliberately choose to clean admin-protected items.

### Decision 3: Categorized failure diagnostics
- **Choice**: In `SystemService.recyclePaths`, analyze failed paths. If any failed path has root ownership (`stat` UID 0), report `isRootOwned = true`. The UI dialog dynamically displays:
  - If root-owned: "检测到管理员权限保护项，由系统管理员 (root) 拥有", with buttons: [稍后处理], [在访达中显示], [授权管理员清理].
  - If Containers/TCC: "包含受 macOS 沙盒保护的 Containers 目录，需要赋予应用「完全磁盘访问权限」", with [打开系统设置].
  - If other: "文件可能被占用或受系统保护", with [在访达中显示].

### Decision 4: Secure administrator elevation via AppleScript
- **Choice**: Implement `SystemService.recyclePathsWithAdminPrivileges(List<String> paths)`.
  It executes:
  ```applescript
  do shell script "chown -R <uid>:<gid> <escaped_paths> && rm -rf <escaped_paths>" with administrator privileges
  ```
  Specifically, try chown and trash; fallback to rm -rf if trash is impossible, followed by post-verification `_pathExists(p)`.
- **Security Whitelist Enforcement**:
  Every path MUST satisfy:
  1. Starts with `$HOME/Library/` or `$HOME/Downloads/` or `/tmp/`.
  2. Does NOT contain `..` or newline/control characters.
  3. Path segment count >= 4 (cannot be root, `/Users`, `$HOME`, or `$HOME/Library`).
  4. Properly single-quoted to eliminate shell injection.

## Risks / Trade-offs

- **[Risk] High-privilege command injection or accidental deletion of system files.**
  - **Mitigation**: Strict whitelist verification rejects any path not inside approved user directories before building the AppleScript command string.
- **[Risk] User cancels password/Touch ID prompt.**
  - **Mitigation**: AppleScript error code 1728 / "User canceled" is cleanly caught, leaving candidate items intact in the list without crashing or false error alerts.
