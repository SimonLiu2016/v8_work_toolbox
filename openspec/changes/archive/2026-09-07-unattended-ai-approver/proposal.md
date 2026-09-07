## Why

在多项目并行与跨终端（iTerm2、系统终端及各类 IDE 终端）开发中，用户经常在离开电脑时运行 AI 任务（如 Claude Code、Antigravity CLI 等）。由于这些工具频繁触发敏感操作交互式授权询问（如命令执行、文件改动），一旦用户不在电脑旁，任务就会被长时间挂起等待人工确认。

此前基于单一项目 `harness` 的 Hook 脚本无法跨项目全局生效，亦无法集中管理多个 AI 客户端。我们需要一个系统级、全局受控的无人值守工具，让用户在离开电脑时一键开启自动审批，同时具备严格的安全机械硬地板（防破坏）与 TTL 超时自动回退（防遗忘），并在 V8WorkToolbox 桌面端提供可视化控制面板与实时审计。

## What Changes

- **全局状态机与状态文件 (`~/.v8worktoolbox/unattended/state.json`)**：提供集中式无人值守开关，支持 TTL 倒计时（如 30m、1h、2h、4h、8h 过夜）与惰性超时判定，超时自动回退到常规人工确认。
- **超轻量全局策略代理脚本 (`v8-approval-proxy`)**：驻留于用户本地系统，响应 Claude Code (`PreToolUse`) 与 Antigravity CLI (`BeforeTool`) 的全局 Hook 协议，毫秒级解析 Tool Call 并根据安全策略决策 `allow` 或 `deny`。
- **安全机械硬地板 (Mechanical Safety Floor)**：内置不可违背的危险操作正则黑名单（毁灭性删除、破坏性 Git 强制推送、机密凭证覆写、远程管道执行等），高危操作直接阻断并触发 macOS 系统桌面通知。
- **全局 Hook 一键挂载管理**：无缝向 `~/.claude/settings.json` 与 `~/.gemini/settings.json` 注册全局代理，同时兼容现有 RTK 等 Hook，不影响日间常规体验。
- **桌面端独立「无人值守助手」页面**：在 V8WorkToolbox 中新增独立的系统工具页面，包含一键状态切换、剩余时长动态倒计时、全局客户端挂载状态卡片、安全黑名单配置表单及实时审批流水审计列表。
- **持久化审计流水 (`audit.jsonl`)**：记录每一笔由无人值守放行或拦截的操作历史，支持在桌面端直接查看、清空与导出。

## Capabilities

### New Capabilities
- `unattended-approver`: 提供无人值守自动审批全流程机制，包括全局状态维护、Hook 协议决策代理、安全机械地板拦截、客户端 Hook 注入与桌面端可视化控制审计。

### Modified Capabilities
<!-- 无既有 spec 需求变更 -->

## Impact

- **桌面端代码**：
  - `lib/tools/registry.dart`: 注册新的 `UnattendedApproverToolDefinition`。
  - `lib/tools/unattended/`: 实现状态控制器、页面 UI (`UnattendedPage`)、状态卡片、倒计时组件与审计流水表格。
  - `lib/services/unattended_service.dart`: 负责读写本地状态、管理 Hook 安装配置、解析审计日志。
- **本地系统环境与配置**：
  - `~/.v8worktoolbox/unattended/state.json` 与 `audit.jsonl`。
  - `~/.claude/settings.json` (追加 `PreToolUse` Hook)。
  - `~/.gemini/settings.json` (追加 `BeforeTool` Hook)。
  - `~/.v8worktoolbox/bin/v8-approval-proxy` (跨客户端执行代理脚本)。
- **依赖与平台**：
  - 纯 macOS 本地平台 Dart/Flutter 原生实现，无外部第三方重度依赖，不破坏既有项目文件。
