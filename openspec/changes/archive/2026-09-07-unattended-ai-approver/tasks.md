## 1. 核心状态机与协议代理实现 (Core State & Approval Proxy)

- [x] 1.1 实现 `UnattendedService` 单例，管理 `~/.v8worktoolbox/unattended/state.json` 与 `audit.jsonl` 的读写
- [x] 1.2 实现 TTL 倒计时状态控制与惰性超时判定（Lazy Expiration）机制
- [x] 1.3 实现安全机械硬地板正则过滤引擎（Denylist matching）与桌面通知触发
- [x] 1.4 实现跨端极速策略代理脚本 `v8-approval-proxy`，支持 Claude Code 与 Antigravity CLI 输入判定

## 2. 全局客户端 Hook 幂等挂载机制 (Global Client Hook Management)

- [x] 2.1 实现 Claude Code 全局配置检测与幂等追加注入（`~/.claude/settings.json` PreToolUse）
- [x] 2.2 实现 Antigravity / Gemini CLI 全局配置检测与幂等追加注入（`~/.gemini/settings.json` BeforeTool）
- [x] 2.3 确保与现有 `rtk` (Rust Token Killer) 等 Hook 数组兼容共存并具备自动备份（`.bak`）机制

## 3. 桌面端「无人值守助手」页面 UI 开发 (Desktop UI Implementation)

- [x] 3.1 创建 `lib/tools/unattended/unattended_page.dart` 页面骨架与主视图架构
- [x] 3.2 实现顶部大开关、动态脉冲状态指示与 TTL 倒计时预设时长胶囊（30m, 1h, 2h, 4h, 8h）
- [x] 3.3 实现全局客户端就绪状态诊断卡片与一键安装/修复操作
- [x] 3.4 实现安全机械硬地板规则管理卡片与展开自定义正则配置
- [x] 3.5 实现实时审批流水审计表格（Audit Stream），支持按客户端过滤、一键清空与日志导出
- [x] 3.6 在 `lib/tools/registry.dart` 中注册 `UnattendedApproverToolDefinition` 并在桌面端导航展现

## 4. 自动化测试与系统验证 (Testing & Verification)

- [x] 4.1 编写 `test/unattended_service_test.dart` 覆盖状态持久化、TTL 超时回退与安全硬地板阻断
- [x] 4.2 编写 Hook 代理脚本输入/输出验证测试（Claude 与 agy 协议 JSON 格式）
- [x] 4.3 运行全量单元与组件测试确认通过
- [x] 4.4 执行 `flutter analyze --no-fatal-infos` 确认 0 错误 0 警告

## 5. 防系统休眠与屏幕常亮实现 (Keep-Awake & Sleep Prevention)

- [x] 5.1 在 `UnattendedService` 中集成基于 `caffeinate -i [-d] -w <pid> -t <sec>` 的进程生命周期管理
- [x] 5.2 在 `UnattendedState` 中增加 `keepDisplayAwake` 配置属性并在开启/关闭及超时回退时联动
- [x] 5.3 在 `UnattendedPage` 界面展示 ☕️ 防休眠状态徽标与“保持屏幕常亮”配置开关
- [x] 5.4 编写防休眠进程启停与生命周期单元测试
- [x] 5.5 全量测试并验证 `flutter analyze` 保持 0 错误 0 警告


