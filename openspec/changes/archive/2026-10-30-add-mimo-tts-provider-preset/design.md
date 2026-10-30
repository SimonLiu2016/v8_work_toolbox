## Context

MiMo 是 OpenAI 兼容供应商，TTS 走 `POST /v1/chat/completions` 的 Chat Audio 规范。引擎侧已就绪：`OpenAiTtsEngine` 已含 `isMimoModel` / `isChatAudioModel` / `adaptVoiceForProvider`（mimo 分支）/ `resolveSystemModel`（mimo 兜底），音色清单在 `TtsVoiceOption.defaultMimoVoices` + `mimoSupportedVoiceIds`。缺的只有配置页的 `MimoPreset` 常量类与快捷 Chip。详见 proposal.md - Why。

## Goals / Non-Goals

**Goals:**
- 一键预填 MiMo API 模式的供应商表单：名称、OpenAI 兼容协议、Base URL、文本/TTS/STT 模型。
- 对齐既有 per-provider preset 模式（`AgnesPreset` / `StepFunPreset` / `QwenPreset`），保持一致性。

**Non-Goals:**
- 不新增 `AiProtocolType` 枚举值（会扩散到 `ai_service.dart` 三处 switch 与 `media_capability.dart::forProtocolId`，且 MiMo 无专用协议语义）。
- 不接 Token Plan 模式（合规风险，见 proposal.md - What Changes）。
- 不修 `testConnection` 的 400/402 雷区，不新增 `MimoAsrClient`（STT 后续独立改动）。

## Decisions

**D1: 用 OpenAI 兼容协议而非新增枚举。**
MiMo 的 `/v1/chat/completions`、`/v1/models` 都是 OpenAI 兼容形态；引擎靠 `xiaomimimo.com` 域名 + `mimo-` 前缀在运行时识别，与协议枚举无关。新增枚举只会给三处 switch 增加必须处理的分支（且各分支逻辑与 openai 完全相同），收益为零。

**D2: 只做 API 模式单一入口，不做双 Chip。**
Qwen 有「Token Plan 会员 / 通用 API」双入口，因为两者都是其合规使用场景。MiMo 的 Token Plan 条款明确禁止非 Coding 场景调用，本 App（阅读器 TTS / 同传 ASR / 字幕）落在违规范围，故仅保留 API 模式入口，避免引导用户触雷。Base URL 只填 `https://api.xiaomimimo.com/v1`。

**D3: 文本模型用 v2.6 系列，TTS 保持 mimo-v2.5-tts。**
2026-10-21 公告下线 v2.5/v2.5-pro 文本模型；`/v1/models` 实测仅剩 `mimo-v2.6-flash` / `mimo-v2.6-pro` / `mimo-v2.6-pro-ultraspeed` 为文本，`mimo-v2.5-tts` / `mimo-v2.5-asr` 为语音。TTS 实测真机出音（HTTP 200，base64 WAV 含合法 RIFF 头）。

**D4: Base URL 覆盖规则沿用 Agnes 先例。**
仅在输入框为空或仍指向其他家默认（如 `api.openai.com`）时覆盖；用户已填的自建网关地址保留。

## Risks / Trade-offs

- **[sk- Key 是 TTS-only]** → 当前 key 对 `mimo-v2.6-*`（402 余额不足）与 `mimo-v2.5-asr`（402）不可用，仅 `mimo-v2.5-tts` 出音。预设不改变测试连接语义；在配置页提示文案中注明「TTS 已验证，文本/STT 需有余额的 Key」。
- **[testConnection 阶段 2 用 user-role ping]** → 对 TTS 模型返回 400（需 assistant-role）。预设预填 `textModels` 首位为 `mimo-v2.6-flash`，若用户仅想测 TTS 会误导；此行为不属本 change 修复范围，仅记录。
- **[Token Plan 条款]** → 不提供入口即不触雷；若用户手动填 `token-plan-*.xiaomimimo.com` + `tp-` key，引擎可工作但属违规使用，超出本 change 可控范围。

## Migration Plan

纯新增 UI 常量与 Chip，无数据迁移、无运行时行为变更（不影响已存 `ai_config.json`）。回滚即移除 Chip 与常量类。

## Open Questions

无。
