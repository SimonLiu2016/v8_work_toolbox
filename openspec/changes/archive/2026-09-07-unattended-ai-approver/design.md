## Context

目前用户在跨项目开发中普遍使用 `claude` (Claude Code) 和 `agy` (Antigravity CLI)，两者均在用户主目录下拥有全局配置：
- `~/.claude/settings.json`：支持 `PreToolUse` hooks（当前已挂载 `rtk hook claude`）。
- `~/.gemini/settings.json`：支持 `BeforeTool` hooks（当前已挂载 `rtk-hook-gemini.sh`）。

Claude Code 官方与实验验证明确：`PreToolUse` hook 在接收到工具调用 JSON 时，若输出 `{"permissionDecision": "allow"}`，即可跳过终端中的交互式确认弹窗；若输出 `{"permissionDecision": "deny", "message": "..."}` 则会安全阻断。

同时，V8WorkToolbox 是基于 Flutter 构建的 macOS 原生桌面工作台，具有统一的 `ToolRegistry` 工具注册机制和现代化暗色风格 UI 体系。

## Goals / Non-Goals

**Goals:**
- **全局生效与跨项目**：无论在任何目录、任何终端（iTerm2、系统终端、VS Code / Cursor 终端）启动的 AI 任务，统一受本系统控制。
- **无常驻能耗**：采用轻量状态文件 + 惰性时间戳校验（Lazy TTL Expiration），无需在系统后台挂载轮询常驻进程。
- **机械硬地板安全拦截**：对高危操作（破坏性删除、Git 强制覆盖、机密凭证篡改、远程管道执行）实施强制阻断，并触发 macOS 系统桌面通知。
- **无缝挂载与兼容性**：自动向全局配置文件追加 Hook 链，与现有的 `rtk` (Rust Token Killer) 等 Hook 和平共存，互不破坏。
- **完整桌面端控制面板**：在 V8WorkToolbox 中提供直观的大开关、TTL 倒计时、客户端连接状态、规则管理与实时审计流水。

**Non-Goals:**
- **终端 Accessibility 屏幕抓取**：第一阶段不依赖复杂的 macOS 辅助功能 GUI 字符匹配，直接走协议级 Hook 保证 100% 精确度。
- **放行人工决策 Gate**：如 `AskUserQuestion` 或 Plan 确认模式，此类交互属于任务逻辑边界，绝对不予自动放行。

## Decisions

### D1 状态文件与目录规范 (`~/.v8worktoolbox/unattended/`)
- 状态存储于用户本地根目录：
  - `~/.v8worktoolbox/unattended/state.json`：包含 `enabled` (bool)、`since` (ISO 8601)、`expiresAt` (ISO 8601)、`ttlMinutes` (int) 以及 `denylist` (正则列表)。
  - `~/.v8worktoolbox/unattended/audit.jsonl`：追加写入的审计日志行。
- **优势**：轻量独立，与 Git 项目无任何耦合；Hook 脚本以毫秒级读取，瞬间完成判定。

### D2 惰性超时退出（Lazy TTL Expiration）
- 用户开启无人值守时设定有效时长（如 2 小时），状态文件记录 `expiresAt`。
- 每次 Hook 脚本被触发时，读取并比对 `DateTime.now() > expiresAt`：
  - 若已超时：Hook 自动就地将 `state.json` 中的 `enabled` 置为 `false`，并退化为默认人工确认行为。
- **替代方案**：起一个后台常驻 daemon 定时 kill/off。**放弃原因**：后台进程存在意外崩溃、开机自启配置复杂和耗电问题，惰性判定零系统负担。

### D3 极速跨端策略代理脚本 (`v8-approval-proxy`)
- 在 `~/.v8worktoolbox/bin/v8-approval-proxy` 生成一个快速可执行代理脚本。
- **判定流程**：
  ```
  AI 发起 Tool Call (stdin JSON)
           │
           ▼
    读取 state.json
           │
     ┌─────┴──────────────────┐
     ▼                        ▼
  enabled == false / 超时    enabled == true 且有效
     │                        │
     ▼                        ▼
  直接退出 (走常规确认)      正则比对 denylist 安全硬地板
                              │
                        ┌─────┴───────────────┐
                        ▼                     ▼
                     命中高危规则          安全命令
                        │                     │
                        ▼                     ▼
                  写入 audit: deny       写入 audit: allow
                  macOS 桌面警报          返回 {"permissionDecision": "allow"}
                  返回 deny 决策
  ```

### D4 安全机械硬地板（Denylist Engine）
- 预置 4 类核心硬地板，禁止自动放行：
  1. `rm\s+-rf\s+[/~.]`：毁灭性全盘/主目录/当前根目录删除。
  2. `git\s+push\s+.*(--force|-f\b)` 与 `git\s+reset\s+--hard`：破坏版本库远端分支与历史。
  3. `>\s*(\.env|.*\.pem|.*\.key|.*id_rsa)`：覆盖写入敏感机密文件。
  4. `(curl|wget)\s+.*\|\s*(bash|sh)`：管道执行不受信网络脚本。
- 支持在桌面端 UI 自定义补充正则表达式。

### D5 全局 Hook 幂等挂载与共存保护
- 读写 `~/.claude/settings.json` 与 `~/.gemini/settings.json` 时先执行备份（`.bak`）。
- 检查 `hooks.PreToolUse`（Claude）与 `hooks.BeforeTool`（Gemini）：
  - 若已包含 `v8-approval-proxy`，保持原样；
  - 若包含其他 hook（如 `rtk hook claude`），以数组追加方式注入，确保两个 hook 链式触发；
  - 提供桌面端“一键检测/修复”与“一键卸载”能力。

### D6 桌面端 UI 模块设计 (`lib/tools/unattended/`)
- `UnattendedService`：单例服务，管理状态读写、TTL 倒计时 Timer、Hook 安装状态核验与 Audit 读取。
- `UnattendedPage`：
  - **顶部 Hero Card**：大开关、脉冲状态指示灯、动态倒计时文字、预设时长胶囊按钮（30m, 1h, 2h, 4h, 8h）。
  - **客户端接入卡片**：Claude Code 与 Antigravity CLI 状态指示与一键挂载。
  - **硬地板策略卡片**：规则列表与开关。
  - **审计流水面板**：带筛选与状态徽章的实时数据表格，支持一键清空日志。

### D7 防系统休眠与屏幕常亮机制 (System Sleep & Display Keep-Awake)
- **核心策略**：基于 macOS 原生 `/usr/bin/caffeinate` 随行进程实现：
  ```bash
  /usr/bin/caffeinate -i [-d] -w <app_pid> -t <ttl_seconds>
  ```
  - **默认必选 `-i`**：防止系统空闲休眠（Idle Sleep），保障后台 CPU 运算与网络连接永不挂起。
  - **按需可选 `-d`**：界面提供“保持屏幕常亮”复选框（默认开启或可配置）。开启时追加 `-d` 阻止息屏；未勾选时允许屏幕息屏省电，系统后台依然全速运转。
  - **双重生命周期锁 (`-w <pid>` + `-t <seconds>`)**：
    - 绑定当前应用 PID，一旦应用被关闭或异常崩溃，操作系统内核瞬时销毁 caffeinate 进程，绝无残留；
    - 结合 TTL 秒数双保险，无人值守到期后自动撤销常亮锁；
    - 用户手动点击“关闭并恢复人审”时，直接向进程发送 `SIGTERM` 信号。

## Risks / Trade-offs

- **[安全残余风险：AI 在放行模式下执行非预期的合法命令]** → 缓解：硬地板牢牢锁住致命操作，同时提供 30 分钟 ~ 8 小时 TTL 档位，用户只在明确离开时开启；桌面端实时保留每条审计日志供事后复盘。
- **[配置文件格式更新或权限冲突]** → 缓解：挂载前先读写测试并留存备份，JSON 序列化保持缩进与原生兼容。
- **[常亮导致的笔记本电池过度消耗]** → 缓解：严格绑定 TTL 倒计时自动退出；提供独立“屏幕常亮”开关，允许仅保系统后台运行而让显示器黑屏省电。

