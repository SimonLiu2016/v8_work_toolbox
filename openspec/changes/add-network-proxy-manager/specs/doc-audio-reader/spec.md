## ADDED Requirements

### Requirement: AI 咨询工具代理开关

AI 咨询工具 SHALL 在其设置或配置区域提供「使用系统代理」开关，该开关独立于其他工具的代理开关持久化。开关开启时，该工具发出的所有 HTTP 请求（AI 对话、MCP 工具调用等）通过 `AppHttpClient` 走 mihomo 代理通道；关闭时直连。

#### Scenario: AI 咨询开启代理后发送请求

- **WHEN** 用户在 AI 咨询工具中开启「使用系统代理」并且全局代理启用（`ProxySettings.isConfigured == true`）
- **THEN** 该工具的 HTTP 请求通过 `127.0.0.1:7890` 发出

#### Scenario: AI 咨询关闭代理后发送请求

- **WHEN** 用户在 AI 咨询工具中关闭「使用系统代理」
- **THEN** 该工具的 HTTP 请求直连，不走 mihomo，与全局代理状态无关
