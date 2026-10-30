## Purpose

提供稳定可靠的 Metasploit RPC (MSFRPC) 守护进程生命周期管控与原生 MSGRPC (MessagePack) 二进制协议通信能力，支撑安全工具箱漏洞验证与渗透执行。

## ADDED Requirements

### Requirement: msfrpcd 守护进程后台启动与探活
系统在未检测到 msfrpcd 服务运行时，SHALL 以后台守护进程模式（免 `-f` 阻塞）启动 `msfrpcd`，并附带 `-n` 禁用无用的数据库配置检查，随后轮询目标端口确认服务处于监听状态，严禁因等待进程退出而发生超时击杀。

#### Scenario: 自动启动后台 msfrpcd 守护进程
- **WHEN** 用户点击“连接”且目标主机/端口尚未运行 msfrpcd 服务
- **THEN** 系统以后台方式拉起 msfrpcd，并在 3 秒内检测到端口建立监听，向用户提示启动成功并进入连接流程

#### Scenario: 本机未安装 Metasploit 时的明确提示
- **WHEN** 用户在未安装 metasploit-framework 的机器上尝试启动或连接 MSFRPC
- **THEN** 系统清晰提示可执行文件缺失，并给出安装指引（如 `brew install metasploit`）

### Requirement: MSGRPC 原生 MessagePack 通信协议
系统与 MSFRPC 服务通信时，SHALL 向 `/api` 端点发送符合 MSGRPC 规范的请求，请求头包含 `Content-Type: binary/message-pack`，请求载荷为 MessagePack 序列化的调用参数数组，并正确解析服务端返回的 MessagePack 响应数据。

#### Scenario: 使用合法凭据登录 MSFRPC
- **WHEN** 用户提供用户名和密码调用登录
- **THEN** 客户端发送 `["auth.login", username, password]` 的 MessagePack 载荷，并从响应中正确解析出临时 Token，标记连接状态为“已连接”

#### Scenario: 登录凭据错误处理
- **WHEN** 用户提供错误的 MSFRPC 密码尝试连接
- **THEN** 服务端返回拒绝响应，客户端友好提示鉴权失败而不会发生网络或协议解析崩溃

### Requirement: MSFRPC 守护进程生命周期控制
系统 SHALL 在漏洞利用面板提供断开连接以及一键停止后台 msfrpcd 守护进程的操作，避免遗留后台冗余进程占用系统资源。

#### Scenario: 用户主动停止 msfrpcd 守护进程
- **WHEN** 用户在漏洞利用面板点击“停止服务”
- **THEN** 系统优雅终止后台运行的 msfrpcd 进程，并重置连接状态为未连接
