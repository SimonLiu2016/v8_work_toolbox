## Purpose

让 Shodan 从"服务层孤岛"变成可用的完整链路：用户能配置 API Key、对资产触发查询、把外部情报（暴露端口、Banner、CVE 标签）合并进资产记录，从而在不出网扫描的情况下补充资产视图。

## MODIFIED Requirements

### Requirement: 外部情报聚合（Shodan/Censys）

系统 SHALL 支持配置 Shodan API Key，通过 `shodan` CLI 或 `uncover` 工具查询目标 IP/组织的暴露服务，将情报结果（暴露端口、Banner、漏洞标签）合并至资产记录。

#### Scenario: 配置 Shodan Key

- **WHEN** 用户在安全工具箱中填写并保存 Shodan API Key
- **THEN** 系统 SHALL 将 Key 持久化到本地配置，下次打开工具箱时保持已配置状态
- **AND** Key SHALL 以脱敏形式展示（仅显示末 4 位），不提供明文回填

#### Scenario: Shodan 资产补充

- **WHEN** 用户对某资产触发"外部情报查询"且 Shodan Key 已配置
- **THEN** 系统 SHALL 查询 Shodan 并将额外信息（CVEs、暴露的服务、组织、ISP、地理位置）追加至该资产记录
- **AND** 查询结果 SHALL 与本地扫描得到的端口合并展示，标注哪些端口来自 Shodan

#### Scenario: 未配置 Key 时禁用入口

- **WHEN** Shodan Key 未配置而用户尝试触发外部情报查询
- **THEN** 系统 SHALL 提示先配置 Key，并引导至配置入口
- **AND** 不发起任何网络请求

#### Scenario: Shodan CLI 未安装

- **WHEN** Key 已配置但本机未安装 `shodan` CLI
- **THEN** 系统 SHALL 提示该工具未安装并给出工具依赖面板入口
- **AND** 资产记录保持不变
