## Why

当前系统缺少自动注册与批量账号生命周期管理能力。用户需要在 V8WorkToolbox 中拥有开箱即用的 Outlook 邮箱自动批量注册能力，同时希望建立系统级「注册工具箱」平台，未来能平滑扩展更多注册类工具。注册成功的账号资产需要支持统一查看、多格式导出、历史 Excel 数据无损导入，并能被密码保险箱及后续其他工具引用。

## What Changes

- **新增「自动注册工具箱」(Auto Registrar Toolbox)**：
  - 接入 Outlook / Hotmail 自动化注册工具（作为首个注册工具实现）。
  - 基于 Node.js + Patchright (CDP 鼠标微动、Arkose/PerimeterX 物理长按、指纹随机伪装、多模态/验证码平台集成、QQ邮箱 IMAP 自动验证码收取与安全邮箱绑定）作为后端 Sidecar 执行引擎。
  - 集成应用已有的网络代理（Mihomo/Clash）能力，支持动态/节点代理分流。
- **中央账号资产库 (Central Account Hub)**：
  - 统一存储注册成功的账号记录（含平台类型、账号、密码、姓名、生日、辅助邮箱、代理IP、注册时间、验活状态等）。
  - 支持按平台/状态筛选、关键字搜索、批量删除。
  - 支持多格式导出（Excel / CSV / TXT / JSON）及密码掩码选择。
  - 支持从 `/Users/simon/Downloads/邮箱信息.xlsx` 等 Excel / CSV 文件导入历史注册账号。
- **跨工具凭证联动与复用 (Cross-Tool Integration)**：
  - 支持一键将选中的账号同步保存至系统级「密码保险箱 (Password Vault)」。
  - 提供通用的账号查询 Service，供系统中后续其他自动化工具或发信工具直接查询和引用有效凭证。

## Capabilities

### New Capabilities
- `auto-registrar`: 自动注册工具箱平台，包含 Outlook 注册引擎、Node Sidecar 进程管理、实时注册统计与日志调度。
- `registered-account-hub`: 统一注册账号资产库，包含账号生命周期存储、历史 Excel/CSV 数据导入、多格式导出、跨工具凭证查询与一键同步至密码保险箱。

### Modified Capabilities
- `password-vault`: 扩展支持批量导入或由外部注册工具箱直接推入凭证条目的接口。

## Impact

- **UI 变化**：活动栏新增「自动注册工具箱」入口；包含「注册任务工作台」与「已注册账号资产库」双选项卡。
- **依赖与运行时**：在应用支持目录维护独立 Node Sidecar 执行环境；新增 Excel 解析导出库支持。
- **跨模块交互**：`registered-account-hub` 依赖 `PasswordVaultStore` 完成凭证互通，依赖 `NetworkProxyService` 获取活跃代理端口。
