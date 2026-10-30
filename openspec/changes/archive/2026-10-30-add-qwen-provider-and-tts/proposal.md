## Why

用户在配置和使用听力练习、文档朗读及 AI 会话等功能时，需要使用千问 AI 平台（`platform.qianwenai.com`）提供的模型服务。当前系统中缺少对千问官方提供商的原生预设与引导，且千问同时存在 Token Plan（订阅套餐，专属端点）与通用 API（按量计费，标准端点）两种接入形态；此外，TTS 引擎在调用 OpenAI 兼容端点时默认选用 `alloy` 等通用音色，当用户选用千问的 CosyVoice/Qwen-Audio-TTS 模型时会因音色不匹配导致合成失败。

本变更正式将千问（Qwen）供应商接入系统 AI 基础设施，提供对 Token Plan 与通用 API 双端点的原生预设支持，并对千问/CosyVoice TTS 进行模型识别与音色自动兼容适配。

## What Changes

- **AI 供应商配置预设增强**：
  - 新增 `QwenPreset` 标准定义：
    - 通用 API Base URL: `https://maas.qianwenaiapi.com/compatible-mode/v1`
    - Token Plan 专属 Base URL: `https://token-plan.maas.qianwenaiapi.com/compatible-mode/v1`
    - 官方推荐文本模型: `qwen3.7-plus, qwen3.7-max, qwen3.8-flash, qwen-max, qwen-plus, qwen-turbo`
    - 官方推荐 STT 模型: `qwen3-asr-flash`
    - 官方推荐 TTS 模型: `cosyvoice-v3-flash, cosyvoice-v3.5-flash, qwen-audio-tts`
  - 在“AI 能力配置”弹窗新增 **`千问 (Token Plan)`** 与 **`千问 (通用 API)`** 两个预设 Chip 按钮，点击一键填入协议（`AiProtocolType.openai`）、地址与对应推荐模型。
- **TTS 引擎智能识别与音色防御**：
  - 在 `OpenAiTtsEngine` 中增加对千问平台及 CosyVoice/Qwen-Audio 系列模型的识别逻辑。
  - 当目标供应商或模型属于千问/CosyVoice 时，若未指定音色或音色属于 OpenAI 默认音色（如 `alloy`），自动智能回退为千问官方推荐音色 `longxiaochun`（或 `Cherry`），杜绝因音色参数错误导致的合成请求失败。
  - 端点自适应：确保无论用户传入基础端点还是带有 `/compatible-mode/v1` 后缀的端点，都能正确拼接 `/audio/speech`。
- **单元测试保障**：
  - 新增针对千问预设配置、槽位推荐与 TTS 音色自适应解析的自动化测试用例。

## Capabilities

### New Capabilities

（无，本改动属于已有 AI 配置基础设施及文档音频阅读器能力的扩展，不新开 capability。）

### Modified Capabilities

- `ai-configuration`: 扩展多协议供应商管理，增加千问（Qwen）原生预设支持（分别支持 Token Plan 与通用 API 双端点），并支持将千问模型绑定至 Text、STT、TTS 槽位。
- `doc-audio-reader`: 增强 OpenAI-Compatible TTS 引擎对千问平台与 CosyVoice/Qwen-Audio 模型的识别能力，支持端点自适应拼接与官方音色智能兜底。

## Impact

**改动代码**：
- `lib/shell/ai_config_page.dart`：定义 `QwenPreset` 常量类，在供应商编辑界面增加两个预设 Chip。
- `lib/tools/reader/services/tts_engine.dart`：在 `OpenAiTtsEngine` 中增加千问/CosyVoice 模型探测及音色智能适配逻辑。
- `test/`：新增预设与 TTS 路径/音色解析相关的自动化测试。

**依赖/数据**：
- 无新增外部依赖；复用既有 `AiProviderConfig` 与安全存储基础设施，向下兼容。
