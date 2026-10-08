## Why

在短视频工坊中生成分镜关键帧时，系统图像生成引擎原先仅支持标准 OpenAI 兼容协议（POST `/v1/images/generations`），无法对接国内视频与图像一体化服务商 SenseAudio（支持自研 SenseAudio-Image-2.0、豆包 Seedream 5.0、SenseNova U1）。由于 SenseAudio 采用独立的 API 协议规范（`/v1/image/sync`、`/v1/image/async` 与 `/v1/image/pending`）且具备严格的图像分辨率白名单限制（如 1080x1920 竖屏会触发 400000 报错），导致关键帧生成失败。此外，当前视频与图像模型属于同一 SenseAudio 供应商，用户需在系统层完成多模态整合，并对图像请求实现双模调度与全链路日志透明化。

## What Changes

- **SenseAudio 专用图像适配器 (`SenseAudioImageAdapter`)**：实现对 SenseAudio 图像生成官方 API 的完整对接，支持方案 C 双模调度（默认使用 `/v1/image/sync` 同步直出；在需要或耗时场景下自适应支持 `/v1/image/async` 任务提交与 `/v1/image/pending` 状态轮询）。
- **智能尺寸规范化吸附 (Resolution Snapping)**：针对 SenseAudio-Image-2.0 及其他模型的合法分辨率列表，自动将工坊请求尺寸（如 1080x1920 竖屏）吸附至合法的最佳比例尺寸（如 1152x2048 或 864x1536），杜绝 400 参数报错。
- **参考图原生 Data URI 注入**：将工坊角色或场景参考图编码为 Base64 Data URI 并注入请求体 `reference` 字段，提升生成分镜的人物与风格一致性。
- **视/图统一供应商整合与预设升级**：在「AI 基础设施配置」中将 SenseAudio 升级为视/图多模态预设，内置 `senseaudio-image-2.0-260319`、`doubao-seedream-5-0-260128`、`sensenova-u1-fast`，同一供应商配置与 API Key 同时供给视频槽位与图像槽位。
- **全链路调用日志记录**：将所有图像生成网络交互统一接入 `AiLogger`，在系统日志及控制台清晰展现请求体、响应体、状态码与错误信息。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 扩展 AI 供应商多模态预设与模型库定义，支持视/图一体化统一供应商，并增强图像生成协议分发与调用日志追踪。

## Impact

- `lib/services/ai_config_store.dart`: 增强 SenseAudio 预设模型定义（多模态视/图合一）。
- `lib/shell/ai_config_page.dart`: 更新 SenseAudio 快速预设按钮，自动填充视频与图像模型列表。
- `lib/tools/ai_video_studio/services/image_gen_adapter.dart`: 新增 `SenseAudioImageAdapter`、分辨率吸附算法，并在 `ImageGenAdapterFactory` 中自适应分发；全面接入 `AiLogger`。
- 测试套件：新增针对 SenseAudio 图像同步/异步接口、错误处理、尺寸吸附与多模态供应商整合的单元测试。
