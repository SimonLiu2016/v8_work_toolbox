# security/web-recon-accuracy Specification

## Purpose
管理安全工具箱 Web 资产侦察中的目标类型识别、输入清洗、根目标保全、死链垃圾数据过滤以及原生 HTTP 存活探测容错。
## Requirements
### Requirement: 目标类型自动识别与子域名枚举分流
系统 SHALL 对用户输入的 Web 侦察目标进行规范化解析与类型识别；对于 IPv4、IPv6、带有私有/内网地址的目标，系统 SHALL 自动跳过子域名枚举阶段，直接执行 HTTP 存活探测。

#### Scenario: 输入局域网路由器 IP 目标
- **WHEN** 用户在 Web 资产侦察输入框中填入 `http://192.168.1.1` 并开始侦察
- **THEN** 系统自动清洗协议头识别为 IP 目标 `192.168.1.1`，日志提示跳过子域名枚举，不调用 subfinder

#### Scenario: 输入公网根域名目标
- **WHEN** 用户输入 `v8en.com` 并开始侦察
- **THEN** 系统识别为标准域名，调用 subfinder 进行被动子域名枚举

### Requirement: 原始根目标全流程保全
系统在进入 HTTP 存活探测（httpx）与后续爬虫阶段时，SHALL 将用户输入的原始目标与枚举出的子域名进行合并去重，严禁丢弃原始根目标。

#### Scenario: 无论是否有子域名均探测原始目标
- **WHEN** 用户输入 `http://192.168.1.1`（或一个未配置任何子域名的网站）
- **THEN** 存活探测列表必定包含 `192.168.1.1` 及其端口，系统对其发起 HTTP 探活并获取网页标题与状态码

### Requirement: 存活优先资产入库
系统在持久化 Web 资产时，SHALL 以 HTTP 存活探测结果为准；未通过存活探测且无法解析的死链字符串，SHALL 不得直接作为正式资产存入会话资产库。

#### Scenario: 过滤失效或被动归档残留的虚假子域名
- **WHEN** 子域名枚举工具从历史归档返回了无法进行 DNS 解析的失效域名（如拼写错误前缀）
- **THEN** 存活探测确认其不可达后，系统不将其沉淀为会话资产，避免污染资产列表

### Requirement: HTTP 探测器环境容错与原生 Fallback
当系统检测到本机外部 `httpx` 工具缺失、被同名 Python 包覆盖或执行异常时，系统 SHALL 自动切换至 Dart 原生 HTTP 客户端探测器，拉取目标状态码、网页标题（Title）与 Web 服务器软件标识。

#### Scenario: 外部 httpx 二进制不可用时测活
- **WHEN** 运行环境中缺少 ProjectDiscovery httpx 二进制，或命令执行失败
- **THEN** 原生探测器成功发起 HTTP 请求，正确记录目标为 200/302 存活资产并解析网页 Title

