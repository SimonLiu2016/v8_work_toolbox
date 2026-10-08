## 1. MessagePack 二进制编解码器实现与单测

- [x] 1.1 在 `lib/tools/security_toolbox/services/msgpack_coder.dart` 中实现轻量纯 Dart MessagePack 序列化器与反序列化器（支持 Null, Bool, Int, String, List, Map, Uint8List）
- [x] 1.2 编写 MessagePack 单元测试，验证标准类型、嵌套 Map/List 以及 MSGRPC 典型报文（如 `auth.login` 数组与服务端返回 Map）的编解码正确性

## 2. MsfRpcService 守护进程管理与 MSGRPC 通信改造

- [x] 2.1 重构 `MsfRpcService.startDaemon`：移除 `-f`，增加 `-n`，实现异步守护进程拉起与快速端口就绪轮询机制
- [x] 2.2 重构 `MsfRpcService._post` 与 RPC 调用：将 URL 端点统一为 `/api`，设置 `Content-Type: binary/message-pack`，使用 MessagePack 编解码收发请求
- [x] 2.3 适配 `auth.login`、`module.execute`、`console.*` 等核心方法的 MSGRPC 格式参数与响应解析
- [x] 2.4 实现 `stopDaemon` 方法，支持用户主动关闭后台运行的 `msfrpcd` 进程

## 3. UI 界面与交互体验优化

- [x] 3.1 在 `lib/tools/security_toolbox/ui/exploit_view.dart` 中优化连接过程的状态提示，并增加停止守护进程按钮
- [x] 3.2 针对可执行文件缺失（未安装 Metasploit）提供精准指引（如 brew install 提示）与友好弹窗

## 4. 验证与端到端测试

- [x] 4.1 运行单元测试与 `flutter analyze` 确保代码规范与测试全部通过
- [x] 4.2 本地真机测试：点击“连接”，验证守护进程自动启动、端口监听检测、MessagePack 登录鉴权以及 Token 获取完整流程

## 5. 强化端口进程精准清理与 401 鉴权错误解析

- [x] 5.1 在 `MsfRpcService.stopDaemon` 中通过 `lsof -ti :<port>` 获取监听该端口的所有 PID 并执行 kill，避免因进程名缩写导致残留僵尸守护进程
- [x] 5.2 在 `MsfRpcService._callRaw` 与 `_attemptLogin` 中，无论 HTTP 状态码是否为 200，只要存在 MessagePack 响应体均进行反序列化，提取真实的 `error_message`（如 Login Failed），杜绝误报“网络或协议异常”
- [x] 5.3 重新构建并替换本机应用（`./scripts/deploy_local.sh`）并验证“停止服务”与“连接”流程

