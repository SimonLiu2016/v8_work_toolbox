# password-vault Specification Delta

## ADDED Requirements

### Requirement: 批量接收外部凭证导入
系统 SHALL 允许内部注册资产库或其他自动化模块以程序化方式批量推入凭证条目，无需用户逐条手动录入。

#### Scenario: 批量导入由注册工具箱推入的登录凭证
- **WHEN** 自动注册账号库调用密码保险箱的批量新增接口传入账号列表
- **THEN** 系统在当前解锁或就绪的 Vault 中批量写入类型为 login 的条目并持久化保存
