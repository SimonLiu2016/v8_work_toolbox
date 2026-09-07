## Context

当前无人值守存在“未开启时不能完全杜绝干涉”、“粗暴正则误伤合法删除（如 `/tmp/xxx` 或 `build/`）”、“未适配 AGY 导致开启依然弹窗确认”以及“审计时区 8 小时偏差”等痛点。本设计提供动态随行生命周期、作用域感知路径解析以及 AGY 原生协议支持。

## Goals / Non-Goals

**Goals:**
- **动态随行生命周期**：开启时自动注入 Hook，关闭/超时到期时自动注销 Hook；未开启时配置零残留，完全不干涉任何 AI。
- **作用域感知边界校验**：能够精准识别 `rm -rf /tmp/xxx` 和 `rm -rf build/` 为安全开发行为（放行），同时坚决阻断 `rm -rf /`、`rm -rf ~`、`rm -rf /System`、`rm -rf .` 等毁灭性操作。
- **AGY 原生协议对接**：在 `~/.gemini/config/hooks.json` 注册 `PreToolUse`，解析 `toolCall.args.CommandLine`，返回标准 `{"decision": "allow"}` 消除终端人机询问。
- **本地时区精准审计**：审计时间转换为本地时间显示，准确区分 `AGY` 与 `Claude Code`。

**Non-Goals:**
- 不接管非命令执行类工具（如只读的文件查看、代码搜索）。

## Decisions

### 1. 动态随行生命周期与零干涉保证
- **架构**：
  - `enable()` 在设置状态的同时自动调用 `installClientHooks()`；
  - `disable()` 与倒计时心跳检测到超时（惰性超时）时，不仅更新状态，还自动触发 `uninstallClientHooks()`；
  - `v8-approval-proxy.js` 执行前置：若 `!state || !state.enabled || isExpired`，立即 `process.exit(0)`，不产生 stdout、不记录任何日志。
- **配置目标**：
  - **AGY**：`~/.gemini/config/hooks.json`，挂载 key 为 `"v8-unattended"`；
  - **Claude Code**：`~/.claude/settings.json`，在 `PreToolUse` 中保留 RTK 等现有 Hook，安全追加或剔除 V8 Hook。

### 2. 作用域路径规范化与三级边界判定
- **路径提取与解析**：
  - 从 `CommandLine` 中提取目标操作路径，并结合执行上下文的 `Cwd`（工作目录）通过 `path.resolve(cwd, target)` 解析出真实绝对物理路径。
- **安全边界模型**：
  1. **禁区（Forbidden）**：
     - 目标路径为 `/` 或用户家目录 `$HOME` 自身；
     - 目标路径为系统核心目录：`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`（除 `/var/tmp` 外）；
     - 目标路径为敏感凭证：`~/.ssh`, `~/.gnupg`；
     - 目标路径解析后等于 `cwd` 本身（防止 `rm -rf .` 毁灭当前项目）；
     - 判定：**DENY 阻断并报警**。
  2. **白名单作用域（Allowed Scopes）**：
     - 目标路径严格位于当前工作区子目录下（`absPath.startsWith(cwd + '/')`）；
     - 目标路径严格位于临时目录下（`absPath.startsWith('/tmp/')` 或 `absPath.startsWith('/var/tmp/')` 且不是 `/tmp` 根目录本身）；
     - 目标路径位于 V8 缓存目录下（`absPath.startsWith('$HOME/.v8worktoolbox/')`）；
     - 判定：**ALLOW 自动放行**。

### 3. AGY 与 Claude Code 协议适配
- **AGY 入参**：`data.toolCall?.name === 'run_command'`，命令位于 `data.toolCall?.args?.CommandLine`，工作目录位于 `data.toolCall?.args?.Cwd`。
- **AGY 出参**：`{"decision": "allow"}` 或 `{"decision": "deny", "reason": "..."}`。
- **Claude Code 出参**：`{"permissionDecision": "allow"}` 或 `{"permissionDecision": "deny", "message": "..."}`。

### 4. 审计日志时区修正
- **前端解析**：`unattended_page.dart` 中读取 `item.timestamp.toLocal()`，格式化为本地时区的 `13:xx:xx`。
- **客户端标签**：根据入参来源精准标注 `AGY`（青色）与 `Claude Code`（紫色）。

## Risks / Trade-offs

- **[风险] 并发命令或多层管道脚本** → **缓解方案**：如果命令包含复杂的 `|` 管道或子 Shell，逐段扫描关键破坏性模式，未命中禁区且在工作区/临时目录内的均安全放行。
- **[风险] 终端异常退出导致 Hook 未卸载** → **缓解方案**：Proxy 脚本拥有独立的本地状态判定兜底，一旦超时或状态为 false，0 毫秒静默直通，完全无感。
