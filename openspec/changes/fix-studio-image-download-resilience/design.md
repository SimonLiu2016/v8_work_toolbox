## Context

在 `SystemAiImageAdapter` 中，文生图 API 请求成功后，返回腾讯云 COS 等云存储 CDN 的公网 URL。此前直接复用默认客户端调用 `get(Uri.parse(url))`，受限于长连接池复用、CDN 节点的激进防盗链与连接重置策略，偶发抛出 `ClientException with SocketException: Connection reset by peer`。

## Goals / Non-Goals

**Goals:**
- 实现专门的稳健图像下载器辅助方法 `downloadImageWithRetry`。
- 下载时注入真实标准浏览器 User-Agent，并显式指定 `Connection: close` 避免 Keep-Alive 复用坏死连接。
- 内置针对 `SocketException`、`HandshakeException`、`ClientException` 或 HTTP 5xx 的最多 3 次指数退避重试。
- 保证下载超时（如 25 秒）可控，防止死锁等待。

**Non-Goals:**
- 不改变生图模型选择或提示词组装逻辑。
- 不影响本地占位图生成逻辑。

## Decisions

### 1. 独立 HTTP 短连接策略
- **决策**: 下载图片时优先采用单次短连接，完成读取后立刻关闭，不与 API 请求共享的长连接池冲突。
- **理由**: 云存储 CDN（COS/OSS）经常在空闲或特定并发窗口主动向客户端发送 TCP RST，复用现有 socket 容易踩到 peer reset。

### 2. 自动退避重试机制
- **决策**: 当捕获到网络层 `SocketException`、`HandshakeException` 或网络层异常时，延时 `500ms * (attempt + 1)` 重新尝试，最多尝试 3 次。
- **理由**: CDN 边缘节点抖动通常极短，快速重试即可成功获取。

## Risks / Trade-offs

- **[Risk]** 重试可能增加整体等待时间 → **Mitigation**: 限制单次下载超时为 25 秒，重试间隔短（500ms~1500ms），总重试时间可控。
