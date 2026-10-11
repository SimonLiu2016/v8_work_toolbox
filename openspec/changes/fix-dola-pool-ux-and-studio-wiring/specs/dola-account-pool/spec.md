## ADDED Requirements

### Requirement: Authentic Dola Login Probing Protocol
系统 SHALL 使用真实上游端点 `POST /alice/user/get_web_anon_id` 结合 BDMS 签名向 Dola 探活，并根据响应头 `x-tt-agw-login: 1` 确认有效性。

#### Scenario: Probe valid cookie
- **WHEN** 用户点击探活有效账号
- **THEN** 系统发起签名请求并收到包含 `x-tt-agw-login: 1` 响应头，更新账号状态为满额/半额并展示有效提示

#### Scenario: Probe expired cookie
- **WHEN** 账号已过期失效
- **THEN** 响应头指示未登录，系统标记该账号为风控/失效状态并给出明确提示
