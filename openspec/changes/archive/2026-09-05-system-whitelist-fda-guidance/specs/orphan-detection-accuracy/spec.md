## ADDED Requirements

### Requirement: 系统原生服务与开发者命令行工具豁免白名单
检测器 SHALL 维护系统核心服务与常见开发者命令行工具的豁免白名单，在遍历 Application Support、Caches 及 Containers 时，直接跳过这些没有独立 .app 安装包的受保护目录，禁止将其误报为孤立残留。

#### Scenario: 豁免 macOS 原生系统级非 com.apple 前缀目录
- **WHEN** 检测器扫描到 `AddressBook`, `GeoServices`, `CoreTelephony`, `CloudDocs`, `MobileSync` 等原生服务目录
- **THEN** 检测器将其直接跳过，不列入候选清理项。

#### Scenario: 豁免常见开发者终端工具与运行时缓存
- **WHEN** 检测器扫描到 `Homebrew`, `rtk`, `claude-cli-nodejs`, `mysql`, `ms-playwright`, `Docker Desktop`, `TabNine` 等 CLI 依赖或后台支撑组件目录
- **THEN** 检测器将其直接跳过，防止开发者工作环境被误清理。
