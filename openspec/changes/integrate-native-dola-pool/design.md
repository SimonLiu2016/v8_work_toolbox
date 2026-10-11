## Context

参考 `proposal.md`。V8WorkToolbox 当前拥有完整的 AI 视频生成抽象层（`VideoGenAdapter`），并已集成本地 Ken Burns 动效、可灵（Kling）、SenseAudio 与 Agnes 适配器。现需要将 Dola 多账号免费池及其逆向纯 HTTP 协议（BDMS 签名）原生内嵌至客户端中，实现免 Docker、零外部进程依赖的端侧视频生成号池。

## Goals / Non-Goals

**Goals:**
- 在客户端工程内轻量化嵌入 BDMS URL 签名守护机制，通过本地管道通信实时签名，无需安装任何 Chrome/Chromium 浏览器。
- 在 Dart 侧建立具备持久化与生命周期的 Dola 账号池服务（`DolaAccountStore` + `DolaPoolScheduler`），实现额度跟踪、东京时间 0 点重置与防风控冷却。
- 实现符合 `VideoGenAdapter` 接口规范的 `DolaPoolVideoAdapter`，支持文生视频、图生视频、进度轮询、无水印成片解析与 30 秒片段组装。
- 在 UI 层提供直观、便捷的 Cookie 批量导入、导出与健康状态检测界面。

**Non-Goals:**
- 不在此阶段引入重量级的浏览器指纹模拟或自动化登录流程（初期通过 Cookie 粘贴导入）。
- 不对外暴露额外的外部 HTTP 端口（号池逻辑完全在 Dart 内部通过内存及管道通信闭环）。

## Decisions

### 1. 签名服务方案：嵌入式 Node 子进程 Daemon
- **决策**：将 `protocol/js/` 下的 `bdms_sign_url.js` 与 `bdms-sdk.js` 复制为工程资源，在 Dart 运行时以 `--daemon` 参数启动单例 Node 子进程，通过 stdin/stdout 行协议进行 JSON-RPC 交互。
- **替代方案**：
  - *启动完整 Python 进程*：增加 Python 运行环境要求和内存开销，被否决。
  - *纯 Dart 逆向重写 BDMS*：SDK 包含 164KB 高度混淆的 VM/AST 虚拟机逻辑，重写难度与维护成本极高，被否决。
- **理由**：macOS 本机自带或开发者环境均有 Node.js；子进程仅占用 20MB 左右内存，单次签名响应在 5~20ms 内，性能极高。

### 2. 账号状态机与额度记账
- **决策**：在 Dart 侧使用结构化 JSON 加密文件持久化存储账号元数据（`name`, `status`, `points`, `last_used_at`, `cooldown_until`），真实 Cookie 存入 Keychain。
  - 满额：4点（可出 1 条 2.0 或 2 条 2.5）
  - 半额：2点（可出 1 条 2.5）
  - 冷却：<=1点（等待东京 0 点自动恢复）
- **理由**：与 Dola 官方实际扣点规则严丝合缝，避免多任务争抢同一账号导致上游封号。

### 3. 30 秒长视频拼合
- **决策**：对于 30 秒请求，优先向上游提交 30 秒参数；若上游仅出 15 秒或两段切片，利用工程内现成的 `FfmpegComposer.runRaw` 进行本地拼接。
- **理由**：充分复用工程现存的音视频底层能力，无需引入第三方去水印或合成接口，保障用户隐私。

## Risks / Trade-offs

- **[Risk] 上游 Dola 前端更新导致 BDMS 签名算法失效** → **[Mitigation]** 签名脚本文件以独立资产目录隔离，协议更新时仅需替换 `bdms-sdk.js` 无需重新编译 Flutter 主体代码。
- **[Risk] 国内直接请求 dola.com 遭遇网络阻塞** → **[Mitigation]** 调度器支持绑定本地已运行的代理节点（如 `127.0.0.1:7890` 或内置 Mihomo 出海节点）。
