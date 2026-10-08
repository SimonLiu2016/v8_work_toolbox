## Why

在安全工具箱的“漏洞利用”模块中，用户点击“连接”MSFRPC 服务时遇到失败：
1. `msfrpcd` 启动命令携带了 `-f`（前台运行）参数，导致进程执行器等待超时（15秒）后直接向进程发送 `SIGKILL` 强行击杀，并误将正常启动提示捕获为“启动失败”；
2. 即使守护进程启动，MSFRPC 默认的 `msgrpc` 协议监听在 `/api` 并强制要求 `binary/message-pack` 二进制协议，而当前客户端使用 `application/json` 发送 REST JSON 请求，服务端抛出 `ArgumentError: Invalid Content Type` 拒绝连接；
3. 缺少对未安装 Metasploit 或连接异常时的精准诊断与指引。

## What Changes

- **守护进程启动重组**：从 `msfrpcd` 启动参数中移除 `-f`（让其自动 fork 后台运行并正常退出父进程），增加 `-n`（禁用数据库检查，消除 `No database YAML file` 警告），并将启动探测从阻塞等待子进程退出改为轮询端口状态。
- **MessagePack 协议集成与 MSGRPC 通信**：
  - 实现纯 Dart 轻量级 MessagePack 编解码支持（无第三方二进制依赖或采用轻量纯 Dart 实现）；
  - 将 `MsfRpcService` 的请求端点统一为 `/api`，Content-Type 设置为 `binary/message-pack`；
  - 规范化 `auth.login`、`module.execute`、`console.*` 等核心 RPC 方法调用的序列化与反序列化逻辑。
- **会话与进程生命周期管理**：
  - 在“漏洞利用”面板中支持精准检测 msfrpcd 状态、优雅停止守护进程；
  - 增强异常捕获，在 Metasploit 未安装时提供明确的安装引导（如 `brew install metasploit`）。

## Capabilities

### New Capabilities
- `security/msfrpc-client`: 管理 Metasploit RPC (MSFRPC) 的守护进程生命周期（后台 fork 启动、探活、停止）以及遵循 MSGRPC 规范的 MessagePack 协议通信（登录鉴权、模块调用、控制台交互）。

## Impact

- `lib/tools/security_toolbox/services/exploit_services.dart`: 重构 `MsfRpcService`，集成 MessagePack 编解码，修正守护进程启动与心跳检查。
- `lib/tools/security_toolbox/ui/exploit_view.dart`: 优化连接状态反馈、守护进程管理及异常提示文案。
- `pubspec.yaml`: 视需要评估是否添加轻量 pure-dart msgpack 依赖或采用内置编解码器。
