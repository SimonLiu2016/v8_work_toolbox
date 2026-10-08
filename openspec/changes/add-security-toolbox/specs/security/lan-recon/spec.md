## Purpose

提供针对本机所在局域网的完整侦察能力：自动识别当前网段、发现所有活跃主机、枚举开放服务与操作系统指纹，并以可视化网络拓扑图呈现，作为 LAN 渗透测试的第一阶段。

## ADDED Requirements

### Requirement: 当前网段自动识别

系统 SHALL 通过解析 `ifconfig` / `ip route` 输出，自动识别本机所有活跃网络接口及对应的 CIDR 网段，供用户一键选择扫描目标，无需手动输入。

#### Scenario: 自动填充网段

- **WHEN** 用户打开 LAN 侦察面板
- **THEN** 系统 SHALL 列出所有活跃网络接口（如 en0: 192.168.1.0/24），用户点击即设置为扫描目标

### Requirement: ARP 主机发现

系统 SHALL 使用 `nmap -sn -PR` 或 `arp-scan -l`（取决于已安装工具）执行 ARP 扫描，在局域网内快速发现所有响应的主机，返回：IP 地址、MAC 地址、推断的设备厂商（OUI）。

#### Scenario: 局域网设备发现

- **WHEN** 用户点击"开始扫描"
- **THEN** 系统 SHALL 在 60 秒内完成 ARP 扫描，实时展示已发现主机列表

#### Scenario: 设备厂商识别

- **WHEN** ARP 扫描发现一个 MAC 地址为 `A4:83:E7:xx:xx:xx` 的设备
- **THEN** 系统 SHALL 显示该设备厂商为 "Apple, Inc."

### Requirement: 服务与端口枚举

系统 SHALL 对已发现主机执行 `nmap -sV -sC -O --open` 深度扫描，获取：开放端口、服务名称与版本、操作系统类型及版本（nmap OS 指纹）。

#### Scenario: 多主机并行扫描

- **WHEN** ARP 发现 20 台主机后用户点击"深度扫描"
- **THEN** 系统 SHALL 并行扫描所有主机，实时更新每台主机的服务信息，总时长不超过 10 分钟

#### Scenario: 扫描结果解析

- **WHEN** nmap XML 输出包含 `<port state="open">` 条目
- **THEN** 系统 SHALL 将端口、服务名、版本信息写入该主机的资产记录

### Requirement: 网络拓扑可视化

系统 SHALL 将 LAN 扫描结果渲染为可交互的网络拓扑图，以网关/路由器为中心节点，各主机为子节点，节点颜色编码风险等级（扫描后漏洞染色），点击节点展示该主机详情。

#### Scenario: 拓扑图渲染

- **WHEN** 至少 2 台主机被发现
- **THEN** 系统 SHALL 以图形方式展示拓扑，节点标注 IP、设备类型图标（PC/手机/路由器/IoT）

#### Scenario: 风险节点高亮

- **WHEN** 某主机有 High 或 Critical 级别的 Finding
- **THEN** 系统 SHALL 将该节点染为红色/橙色，悬停显示漏洞摘要

### Requirement: 扫描配置灵活性

系统 SHALL 支持扫描深度配置：快速模式（top 100 ports，~2 分钟）、标准模式（top 1000 ports，~5 分钟）、全端口模式（1-65535，~20 分钟），用户可针对单个主机或整个网段选择模式。

#### Scenario: 快速模式扫描

- **WHEN** 用户选择"快速模式"并启动扫描
- **THEN** 系统 SHALL 使用 `nmap -F` 参数，仅扫描常用 100 端口
