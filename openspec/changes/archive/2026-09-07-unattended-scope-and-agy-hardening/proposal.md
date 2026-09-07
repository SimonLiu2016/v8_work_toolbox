## Why

在无人值守功能的实际使用与测试中，发现了以下影响核心体验的关键问题：
1. **生命周期不干涉原则缺失**：未开启无人值守时，不应当干预或拦截任何 AI 行为；开启无人值守时，应当自动生效，无需反复人工配置；关闭或超时后，应自动恢复纯净环境。
2. **缺乏作用域感知（Scope-Aware）**：安全硬地板仅靠粗暴的正则表达式，无法区分 `rm -rf /`（灾难性破坏）与 `rm -rf /tmp/xxx` 或 `rm -rf build/`（正常的开发构建清理），导致正常开发动作被误伤。安全判定必须结合命令目标的作用域与物理边界。
3. **未真实适配 Antigravity CLI (AGY)**：之前的 Hook 仅按旧版配置写入，未对接 AGY 真实的 `~/.gemini/config/hooks.json`、`PreToolUse` 及 `toolCall.args.CommandLine` 协议，导致开启后 AGY 终端依然频繁弹出人机确认；
4. **审计流水时区与数据偏差**：审计日志时间未转本地时区（出现 8 小时 UTC 偏差），且客户端标识未能准确反映真实的 AGY 客户端。

## What Changes

- **动态随行生命周期管理**：
  - 开启无人值守时：原子化向 AGY（`~/.gemini/config/hooks.json`）与 Claude Code（`~/.claude/settings.json`）挂载 Hook，启用防休眠；
  - 关闭或 TTL 超时失效时：**全自动从配置文件中移除 V8 Hook**，恢复环境原始状态；
  - Proxy 脚本增加静默双保险：若 `state.enabled == false`，立即 exit 0 无输出退出，绝对零干涉。
- **作用域与边界安全判定引擎 (Scope-Aware)**：
  - 从 `CommandLine` 与工作目录 (`Cwd`) 解析目标路径规范化绝对路径；
  - 建立三级安全边界：
    - **白名单放行**：工作区子目录（如 `build/`、`.dart_tool/`、`node_modules/`）与系统临时目录（`/tmp/*`、`/var/tmp/*`）；
    - **绝对禁区阻断**：系统根目录 `/`、用户主目录 `~`、系统顶级目录（`/System`、`/Library`、`/usr` 等）、敏感凭证（`~/.ssh`）及试图跳出工作区根部的破坏性操作。
- **AGY 原生协议对接与免密全自动审批**：
  - 精准解析 `toolCall.args.CommandLine`，返回 AGY 标准 `{"decision": "allow"}`（完全放行免密执行）或 `{"decision": "deny"}`（阻断）；
  - 保留并兼容 Claude Code（`{"permissionDecision": "allow"}`）及 RTK 等既有 Hook。
- **审计流水与时区修复**：
  - UI 统一使用 `timestamp.toLocal()` 显示本地精确时间（13:xx:xx）；
  - 准确显示客户端标签（`AGY` / `Claude Code`），清理历史 mock 残留数据，实时展示真实审计流水。

## Capabilities

### New Capabilities
- `unattended-approver`: 完善具备动态随行生命周期、作用域感知边界校验以及 AGY/Claude 双协议无感自动审批的无人值守服务。

## Impact

- `lib/services/unattended_service.dart`（动态生命周期、AGY hooks.json 挂载与卸载、作用域判定逻辑、本地时区转换）
- `lib/tools/unattended/unattended_page.dart`（状态展示、审计时间格式化、AGY 客户端标签）
- `~/.v8worktoolbox/bin/v8-approval-proxy.js`（AGY 入参解析与作用域判定引擎）
- `test/unattended_service_test.dart`（单元测试更新与作用域边界验证）
