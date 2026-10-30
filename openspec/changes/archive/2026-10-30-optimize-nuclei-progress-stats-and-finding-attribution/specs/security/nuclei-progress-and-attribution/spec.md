## Purpose

为安全工具箱漏洞扫描提供 Nuclei 周期性统计进度可视化、目标资产精准匹配归属与漏洞发现物列表明确展示。

## ADDED Requirements

### Requirement: Nuclei 扫描进度实时统计可视化
系统在执行 Nuclei 扫描时，SHALL 开启引擎统计流机制（如 `-stats -si`），捕获周期性运行进度数据并在控制台及前端界面呈现实时动态反馈。

#### Scenario: 扫描执行中的周期性进度日志输出
- **WHEN** Nuclei 扫描正在后台运行多个模板及目标
- **THEN** 系统每隔固定周期（如 5 秒）输出包含完成百分比、已发请求数、当前请求速率与发现物数量的易读日志，不出现长时间静默无输出

#### Scenario: 进度百分比与计数回调
- **WHEN** 捕获到合法的统计 JSON 行
- **THEN** 系统提取已完成请求数与总请求数并触发进度回调，供前端展示进度指示

### Requirement: 带端口网络目标的资产精准匹配
系统在处理 Nuclei 发现物（Finding）的 `matchedAt` 字段时，SHALL 正确解析带有端口号的 TCP/HTTP 目标（如 `host:port` 或 `http://host:port`），准确提取主机名并关联至所属资产。

#### Scenario: TCP 端口探测发现物的资产归属关联
- **WHEN** Nuclei 匹配到网络服务（如 `matchedAt` 为 `www.v8en.com:22`）
- **THEN** 系统提取出纯主机名 `www.v8en.com`，成功关联到对应会话资产并持久化存储 `assetId`

### Requirement: 漏洞发现物列表显式标注所属目标
系统在漏洞发现物列表中展示各个风险项时，SHALL 明确显示该项发现所归属的目标地址或端点，避免同名服务检测项出现视觉重复混淆。

#### Scenario: 多子域名同名检测项清晰区分
- **WHEN** 多个子域名均开放了同种服务或存在同名配置项（如多个子域名均命中 `OpenSSH Service - Detect`）
- **THEN** 列表中每条发现物项均显式显示其所对应的目标地址标签（如 `www.v8en.com:22` 与 `admin.v8en.com:22`），用户可一眼区分不同主机的发现

### Requirement: 漏洞扫描严重级别过滤
系统 SHALL 允许用户在发起漏洞扫描前配置模板的危险等级（Severity），过滤非关心的轻量级嗅探规则。

#### Scenario: 过滤低危与信息探测规则
- **WHEN** 用户选择仅扫描 `Critical / High / Medium` 等级的漏洞模板
- **THEN** 系统向 Nuclei 传递对应的 `-severity` 参数，忽略不必要的 Info 级别探测模板，大幅缩短总体扫描耗时
