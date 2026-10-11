## Why

用户中转站（NewAPI / 供应商网关）已挂载 Agnes 图像与视频模型（`agnes-image-2.5-flash` 与 `agnes-video-2.5-flash`），但分镜看板生图时因协议与参数结构不兼容而报错。为彻底解决接入兼容性并支持中转站多账号统一管理，系统需要引入原生 `agnes` 专用协议，统一并固定图片（`/v1/images/generations`）与视频（`/v1/videos`）的 Endpoint 规范与精简请求入参，无缝兼容自建中转站与官方 Hub。

## What Changes

- 在 AI 配置核心协议枚举 `AiProtocolType` 中新增 `agnes`（Agnes 专用协议）。
- 在设置页供应商添加/编辑表单中增加「Agnes 专用协议」选项及「Agnes / 中转站 (视/图多模态)」快速预设。
- 规范化 `SystemAiImageAdapter`：针对 Agnes 协议或 `agnes-image` 模型，固定 Endpoint 为 `/v1/images/generations`，严格精简请求体为 `{"model": "...", "prompt": "..."}` 标准字段，避免官方专属字段导致中转站报错。
- 规范化 `AgnesVideoAdapter`：视频任务创建固定为 `POST /v1/videos`，状态轮询优先兼容通用 OpenAI Videos 端点 `/v1/videos/{task_id}` 并兜底官方端点。
- 在 `AiService` 统一路由中，将 `AiProtocolType.agnes` 的文本对话与模型探测对齐 OpenAI 兼容规范，保证中转站全功能可用。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 扩展 AI 供应商协议类型，增加 `agnes` 专用协议支持与对应预设配置。

## Impact

- `lib/services/ai_config_store.dart`: 枚举 `AiProtocolType` 新增 `agnes`。
- `lib/services/ai_service.dart`: 对话路由与模型探测支持 `AiProtocolType.agnes`。
- `lib/shell/ai_config_page.dart`: 供应商协议选择与预设增加 Agnes 模板。
- `lib/tools/ai_video_studio/services/image_gen_adapter.dart`: 图像适配器精简参数与路径对齐。
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: 视频适配器接口与轮询路径对齐。
