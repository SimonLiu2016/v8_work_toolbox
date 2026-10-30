## Context

目前安全工具箱在 `lib/tools/security_toolbox/services/exploit_services.dart` 中集成了 `MsfRpcService`，但由于启动参数误传 `-f` 导致进程阻塞并在 15 秒后被 SIGKILL 终止。此外，客户端请求发送的是 JSON 格式，而 macOS Metasploit 的 MSFRPC 服务默认使用 `msgrpc` (MessagePack-RPC) 协议。

## Goals / Non-Goals

**Goals:**
- 修复 `msfrpcd` 启动机制：移除 `-f`，增加 `-n`，以纯后台守护进程方式启动，并通过端口探活检测就绪状态。
- 实现一个纯 Dart 的轻量级 MessagePack 编解码器（支持 Uint8List 二进制序列化和反序列化 Map/List/String/Int/Bool/Null），无需引入庞大的外部 C 库或破坏跨平台兼容性。
- 将 `MsfRpcService` 通信端点切换为 `/api`，传输 `Content-Type: binary/message-pack`，遵循 Metasploit 原生 MSGRPC 格式。
- 优化连接异常处理与退出清理逻辑，提供停止守护进程能力。

**Non-Goals:**
- 不依赖已废弃且 macOS 上缺少配置文件的 `msfrpcd -j` (JSON-RPC) 模式。
- 不强制要求本地配置 PostgreSQL 数据库（`-n` 保持轻量独立运行）。

## Decisions

### 1. 启动模式：脱离前台运行与添加 `-n` 参数
- **决策**：执行 `msfrpcd -P <pwd> -a <host> -p <port> -S -n`（无 `-f`）。
- **理由**：`msfrpcd` 自带守护进程化能力（后台 fork，主进程打印 PID 后退出 0）。`runCaptured` 可以迅速收到父进程退出的返回值（耗时 < 1 秒），随后使用短延时轮询（例如最多 3 秒）探测 `Socket.connect(host, port)`，一旦端口打通即可确定守护进程成功就绪。
- **备选方案**：使用 `Process.start` 保持子进程句柄。缺点是当应用退出时孤儿进程处理复杂；而让 `msfrpcd` 自行 daemonize 并通过 PID 记录或端口管理更加稳定。

### 2. MessagePack 协议：实现纯 Dart 微型编解码器
- **决策**：在 `exploit_services.dart` 或独立文件 `lib/tools/security_toolbox/services/msgpack_coder.dart` 中实现精简的纯 Dart MessagePack Codec。
- **理由**：
  - MSFRPC 的协议只包含基本类型：`fixarray`、`array16/32`、`fixmap`、`map16/32`、`fixstr`、`str8/16/32`、整数（positive/negative fixint, uint8..64, int8..64）、`bool`、`nil`、`bin8/16/32`；
  - 纯 Dart 实现代码量仅约 150 行，零外部依赖，极快且不会引起 pub 依赖冲突或打包问题。
- **备选方案**：引入 `pub` 依赖 `msgpack_dart`。虽然可行，但纯 Dart 自研微编解码器完全自包含，无版本漂移风险。

### 3. API 路由与 MSGRPC 请求包装
- **决策**：
  - 目标 URL：`http://${config.host}:${config.port}/api`
  - 登录：序列化为 MessagePack 数组 `['auth.login', config.username, config.password]`
  - 请求头：`Content-Type: binary/message-pack`
  - 响应解析：从 HTTP 响应的二进制字节流反序列化为 Dart `Map<dynamic, dynamic>`，读取 `result` 和 `token`。

## Risks / Trade-offs

- **[Risk] 用户环境端口占用** → **Mitigation**: 启动前先检查目标端口，若已有服务运行则直接尝试认证；提供明确的错误提示说明端口冲突。
- **[Risk] Metasploit 启动稍慢 (冷启动约 2~3 秒)** → **Mitigation**: 启动守护进程后轮询端口 10 次（每次 300ms），给 Ruby 虚拟机充足的初始化时间。
