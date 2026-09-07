## 1. 动态随行生命周期重构 (Dynamic Accompanying Hook Lifecycle)

- [x] 1.1 重构 `enable()`，使其原子化注入 Hook 至 AGY (`~/.gemini/config/hooks.json`) 与 Claude Code (`~/.claude/settings.json`)
- [x] 1.2 重构 `disable()` 与倒计时超时，使其自动从 AGY 与 Claude Code 配置文件中完全移除 Hook 恢复纯净环境
- [x] 1.3 强化 Proxy 脚本前置安全门禁：未激活或超时时 0 毫秒立即 exit 0 无输出退出，确保零干预

## 2. 作用域感知与路径边界判定引擎 (Scope & Boundary-Aware Safety Engine)

- [x] 2.1 重写 `_buildProxyJsContent()` 中的命令与路径解析，提取 `CommandLine` 与 `Cwd`
- [x] 2.2 实现三级边界校验：精准放行当前工作区子目录（`build/`、`.dart_tool/` 等）与系统临时目录（`/tmp/*`）
- [x] 2.3 坚决阻断绝对禁区：系统根目录 `/`、家目录根基 `~`、系统核心目录、敏感凭证及试图跳出工作区根部的破坏性删除
- [x] 2.4 在 Dart 端 `evaluateCommand` 中同步实现同构的作用域感知判定逻辑

## 3. AGY 原生协议对接与免密全自动审批 (AGY & Claude Native Protocols)

- [x] 3.1 适配 AGY `PreToolUse` 输入输出协议（解析 `toolCall.args.CommandLine`，返回 `{"decision": "allow"}` 与 `{"decision": "deny"}`）
- [x] 3.2 保留对 Claude Code 协议（`{"permissionDecision": "allow"}`）与现有 RTK Hook 的幂等共存与无缝串联

## 4. 审计流水时区与 UI 体验优化 (Audit Stream Local Time & UI Polish)

- [x] 4.1 修复 `unattended_page.dart` 中时间展示的 8 小时 UTC 时差，统一使用 `timestamp.toLocal()` 显示准确本地时间
- [x] 4.2 审计流水展示准确的客户端标识（`AGY` 青色标签，`Claude Code` 紫色标签）
- [x] 4.3 增加审计流水“清空记录”与“导出”操作，并清理单元测试残留的假数据

## 5. 全面验证与构建打包 (Verification & Deployment)

- [x] 5.1 运行单元测试覆盖作用域边界（`/tmp/xxx` 放行 vs `/` 拦截）与动态生命周期挂载/卸载
- [x] 5.2 重新编译并同步安装至 `/Applications/V8WorkToolbox.app`
