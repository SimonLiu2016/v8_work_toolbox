## 1. 注册核心 Sidecar 提取与打包

- [x] 1.1 从 mail_tools 提炼并重构注册引擎为独立 Node Sidecar CLI (`packages/registrar_sidecar`)，支持 Stdio JSON-RPC 控制与流式日志推流
- [x] 1.2 保留全部 anti-detect 特征、PerimeterX / Arkose 物理长按、AI视觉/CapSolver 识别、QQ邮箱 IMAP 验证码收取与安全邮箱绑定
- [x] 1.3 编写 Sidecar 的自检与启动测试脚本，确保在 macOS 环境下可独立唤起执行

## 2. 账号资产库 (RegisteredAccountHub) 核心服务实现

- [x] 2.1 建立 `RegisteredAccount` 数据模型与安全存储机制 (`lib/tools/auto_registrar/models/` 及 `services/registered_account_store.dart`)
- [x] 2.2 实现 Excel (`.xlsx`) 与 CSV 导入解析逻辑，完成对 `/Users/simon/Downloads/邮箱信息.xlsx` 57个账号的结构化导入与去重验证
- [x] 2.3 实现多格式导出能力（Excel, CSV, TXT, JSON，支持密码掩码）
- [x] 2.4 实现跨模块凭证同步：在 `PasswordVaultStore` 扩充批量接收接口，并在账号库实现「一键同步至密码保险箱」

## 3. Flutter 端「自动注册工具箱」UI 与控制台开发

- [x] 3.1 创建工具定义 `AutoRegistrarToolDefinition` 并注册进 `lib/tools/registry.dart` 与侧边栏
- [x] 3.2 实现「任务注册控制台」页面：包含并发设置、域名选择、验证码与IMAP配置、实时日志终端和统计指标卡片
- [x] 3.3 实现「中央账号资产库」管理页面：包含账号列表数据表格、筛选搜索、密码显隐、批量删除、导入/导出以及一键同步到密码保险箱操作栏
- [x] 3.4 联调 Node Sidecar 与应用内置代理（NetworkProxy）联动，支持直连与本地代理通道分流

## 4. 验证、自动化构建与本地部署

- [x] 4.1 自动执行历史文件 `/Users/simon/Downloads/邮箱信息.xlsx` 导入，验证所有账号在 UI 中正常呈现
- [x] 4.2 验证账号批量推入「密码保险箱」后的条目正确性
- [x] 4.3 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh` 编译 Release、更新 `/Applications/V8WorkToolbox.app` 并完成最终验证
