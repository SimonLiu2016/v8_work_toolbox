## Context

短视频工坊关键帧需要高品质图像生成支持。目前全局系统配置已支持 `image` 槽位，但其适配器默认遵循 OpenAI `/v1/images/generations` 协议。SenseAudio（拥有自研 SenseAudio-Image-2.0、豆包 Seedream 5.0、SenseNova U1 等优质模型）使用专属的 `/v1/image/sync`、`/v1/image/async`、`/v1/image/pending` 规范，且对尺寸有严格白名单，工坊默认的 1080x1920 尺寸会直接触发 400 校验错误。此外，SenseAudio 在系统中既是视频提供商又是图像提供商，应实现单一供应商多模态合一与全链路调用日志。

## Goals / Non-Goals

**Goals:**
- 实现方案 C（双模自适应图像生成）：优先调用 `/v1/image/sync` 快速直出图片；同时完整实现 `/v1/image/async` 任务提交与 `/v1/image/pending` 轮询逻辑，支持任务超时、取消与细粒度进度反馈。
- 实现模型尺寸智能吸附（Resolution Snapping）：针对 `senseaudio-image-2.0-260319` 及其他模型，将任意宽高输入（如 1080x1920 竖屏、1920x1080 横屏）根据宽高比（Aspect Ratio）吸附到最近的官方支持尺寸（如 `1152x2048` 或 `2048x1152`）。
- 支持分镜角色/场景参考图编码为 Base64 Data URI 透传至 `reference` 字段。
- 在 `ImageGenAdapterFactory` 中自适应探测并分发：SenseAudio 走专属适配器，其他走通用 OpenAI 兼容适配器。
- 视/图同一供应商多模态预设升级：更新预设填充模板，同一 API Key 供双槽位共享。
- 全链路调用接入 `AiLogger`，在日志控制台与本地日志中输出规范记录。

**Non-Goals:**
- 不拆分 SenseAudio 为两个独立的系统供应商实体，维持统一的供应商记录。
- 不修改分镜看板或剧集内部存储的 1080x1920 基础规格定义，仅在向 SenseAudio 发起网络请求时做透明吸附映射。

## Decisions

### D1: 双模自适应调度 (Dual-mode Adaptive Strategy)
- **决定**：默认发起 `POST /v1/image/sync` 同步出图。当同步请求超时或服务端返回指示需要排队处理时，平滑降级或允许配置为 `POST /v1/image/async` + `GET /v1/image/pending` 异步轮询。
- **替代方案考虑**：纯同步模式在网络极慢或高分辨率渲染时可能触发客户端 HTTP 超时；纯异步模式会带来无谓的轮询开销。双模自适应兼具低延迟与高鲁棒性。

### D2: 宽高比智能吸附算法 (Aspect Ratio Snapping Algorithm)
- **决定**：计算目标宽高的比例 $R = \text{width} / \text{height}$。在模型允许的尺寸列表中，优先过滤同朝向（横版 $R > 1.1$、竖版 $R < 0.9$、方形 $0.9 \le R \le 1.1$），并在该子集中选取欧式像素差距或比例差距最小的合法尺寸。例如 1080x1920 ($R = 0.5625$) 自动映射到 1152x2048 ($R = 0.5625$，精确一致）。
- **替代方案考虑**：强制要求用户在 UI 下拉框选择尺寸。缺点是打断了短视频工坊自动化一键出图的顺畅体验。

### D3: 适配器工厂透明分发 (Adaptive Adapter Dispatch)
- **决定**：`SystemAiImageAdapter` 内部聚合或分发到 `SenseAudioImageAdapter` 与 `OpenAiCompatibleImageAdapter`。当活跃的系统图像供应商 Base URL 包含 `senseaudio.cn` 或名称匹配 SenseAudio 时，自动启用 SenseAudio 专用协议与尺寸吸附；其他供应商沿用标准 OpenAI 图像协议。
- **替代方案考虑**：让用户在工坊设置下拉框里分选 `system-senseaudio` 和 `system-openai`。缺点是增加了认知负担，打破了“跟随系统全局配置”的纯净抽象。

### D4: 全链路日志注入 (Full AiLogger Integration)
- **决定**：在适配器发出 HTTP 请求前后分别调用 `AiLogger.logRequest` 和 `AiLogger.logResponse` / `AiLogger.logError`，记录 URL、请求体 JSON、HTTP 状态码及返回体。

## Risks / Trade-offs

- **[Risk]** SenseAudio 官方以后可能调整合法尺寸列表。
  - **Mitigation**: 尺寸映射表集中定义并提供清晰的缺省兜底（如默认 `1152x2048` 竖版与 `2048x1152` 横版），并在单元测试中覆盖常见分辨率。
- **[Risk]** 同一供应商下密钥失效会同时影响视频与图像。
  - **Mitigation**: 在设置弹窗和 AI 配置页面分别提供连通性测试，实时反馈可用性状态。
