## Purpose

管理应用内嵌的代理能力——从 Clash 订阅地址获取代理节点列表，通过捆绑的 mihomo 内核建立本地 HTTP 代理出口，支持节点选择、延迟测试与订阅刷新，代理作用域严格限于本应用进程发出的 HTTP 请求，不修改任何 macOS 系统代理设置。

## ADDED Requirements

### Requirement: 订阅地址管理

应用 SHALL 允许用户配置一个 Clash 兼容格式的订阅 URL，并持久化到本地配置文件。订阅 URL 的内容 SHALL 在用户主动触发「刷新订阅」时下载并解析，不得在后台静默自动刷新。

#### Scenario: 保存订阅地址

- **WHEN** 用户在「网络代理」页输入订阅 URL 并点击「保存」
- **THEN** URL 持久化到本地配置，并在 UI 显示上次保存时间

#### Scenario: 订阅 URL 为空时保存

- **WHEN** 用户提交空的订阅 URL
- **THEN** 系统阻止保存并提示「订阅地址不能为空」，已有配置保持不变

### Requirement: Clash YAML 订阅解析

应用 SHALL 通过 HTTP GET 请求下载订阅 URL 内容，解析 YAML 中的 `proxies:` 字段，提取所有代理节点（支持 VMess、VLESS、Shadowsocks、Trojan、Hysteria2、TUIC 等协议字段），并将节点列表持久化到本地。

#### Scenario: 成功刷新订阅

- **WHEN** 用户点击「刷新订阅」且订阅 URL 可访问
- **THEN** 系统下载 YAML、解析节点列表并在 UI 中展示节点名称和协议类型，展示刷新完成时间

#### Scenario: 订阅下载失败

- **WHEN** 网络不可达或服务器返回非 200 状态码
- **THEN** 系统显示具体错误原因（如「连接超时」「HTTP 404」），保留上次成功解析的节点列表，不清空现有列表

#### Scenario: YAML 格式无效或无代理节点

- **WHEN** 下载内容无法解析为有效 YAML 或 `proxies:` 字段为空
- **THEN** 系统显示「订阅内容无效，未找到代理节点」，保留上次成功的节点列表

### Requirement: 节点列表展示与选择

应用 SHALL 在「网络代理」页展示所有已解析节点，每个节点显示名称、协议类型和最近一次延迟测试结果。用户 SHALL 能单选一个节点作为当前活跃代理；选中后 mihomo 立即以该节点配置重启。

#### Scenario: 选择节点

- **WHEN** 用户点击列表中的某个节点
- **THEN** 该节点被标记为「选中」，mihomo 以该节点的配置重新启动，UI 显示「代理运行中 127.0.0.1:7890」

#### Scenario: 无节点可选

- **WHEN** 节点列表为空（未刷新订阅或解析失败）
- **THEN** UI 显示「尚无节点，请先刷新订阅」，代理为停止状态

### Requirement: 节点延迟测试

应用 SHALL 支持对单个节点或全部节点进行延迟测试，测试结果（毫秒数或「超时」）实时更新到节点列表。延迟测试通过 mihomo REST API 发起，测试地址为 `http://www.gstatic.com/generate_204`，超时阈值 5000ms。

#### Scenario: 全部测速

- **WHEN** 用户点击「全部测速」
- **THEN** 系统对每个节点并发发起延迟测试，结果逐步更新到列表，完成后各节点显示延迟值或「超时」

#### Scenario: 单节点测速

- **WHEN** 用户点击某节点旁的测速按钮
- **THEN** 仅对该节点发起延迟测试并更新其延迟显示

### Requirement: mihomo 进程生命周期管理

应用 SHALL 在用户选中节点后启动捆绑的 mihomo 二进制进程，监听 `127.0.0.1:7890`（HTTP）。应用退出时 mihomo 进程 SHALL 同步终止。若 mihomo 进程意外崩溃，UI SHALL 更新状态为「代理已停止」。mihomo 进程 SHALL NOT 修改 macOS 系统代理设置。

#### Scenario: 应用正常退出时 mihomo 停止

- **WHEN** 用户退出应用
- **THEN** mihomo 子进程在应用退出前被终止，不留后台孤儿进程

#### Scenario: mihomo 意外崩溃

- **WHEN** mihomo 子进程意外终止
- **THEN** UI 状态更新为「代理已停止（进程异常退出）」，不自动重启，等待用户重新选择节点

#### Scenario: 未选中节点时代理为停止状态

- **WHEN** 应用启动且无持久化的选中节点
- **THEN** mihomo 不启动，代理状态为「未运行」

### Requirement: 全局代理启用开关

「网络代理」页 SHALL 提供全局启用/禁用开关。禁用时 `ProxySettings.isConfigured` 返回 `false`，所有工具均直连，mihomo 进程继续运行但不被使用。

#### Scenario: 全局禁用代理

- **WHEN** 用户关闭全局代理开关
- **THEN** `ProxySettings.enabled` 变为 `false`，后续所有工具的 HTTP 请求走直连，mihomo 进程不停止

#### Scenario: 全局重新启用代理

- **WHEN** 用户重新打开全局代理开关且已有选中节点
- **THEN** `ProxySettings.enabled` 变为 `true`，后续请求再次走 mihomo 代理通道
