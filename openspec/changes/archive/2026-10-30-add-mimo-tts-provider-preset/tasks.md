## 1. MimoPreset 常量类

- [x] 1.1 在 `lib/shell/ai_config_page.dart` 的既有预设类区（`QwenPreset` 之后）新增 `abstract final class MimoPreset`，定义 `displayName = 'Mimo (小米)'`、`baseUrl = 'https://api.xiaomimimo.com/v1'`、`textModels = 'mimo-v2.6-flash, mimo-v2.6-pro'`、`ttsModels = 'mimo-v2.5-tts'`、`sttModels = 'mimo-v2.5-asr'`，并加注释说明「仅 API 模式；Token Plan 因官方非 Coding 场景禁令不提供入口」。
- [x] 1.2 校验常量值：`textModels` 不含已下线的 `mimo-v2.5`/`mimo-v2.5-pro`；`baseUrl` 不含 `token-plan-`；TTS 模型为 `mimo-v2.5-tts`。

## 2. 快速填充 Chip

- [x] 2.1 在「快速填充预设」`Wrap` 中、`OpenRouter` Chip 之后新增 MiMo `ActionChip`（icon 可用 `Icons.record_voice_over_outlined`），onPressed 中 `setDialogState` 预填 `nameCtrl` / `protocol = AiProtocolType.openai` / `urlCtrl` / `modelsCtrl` / `ttsModelsCtrl` / `sttModelsCtrl`。
- [x] 2.2 Base URL 覆盖规则沿用 Agnes 先例：仅当 `urlCtrl.text` 为空或包含 `openai.com` 时覆盖为 `MimoPreset.baseUrl`；否则保留用户已填地址。
- [x] 2.3 协议提示区：MiMo 走 OpenAI 兼容协议，无需像 stepfun/openrouter 那样加条件提示块；如需要可加一条与 `Agnes` 一致的简短说明（可选，若加则用 `Icons` 对齐既有风格）。

## 3. 测试

- [x] 3.1 在 `test/tts_engine_provider_transparency_test.dart` 的「Presets & Config Self-Healing」组新增断言：`MimoPreset.baseUrl` 等于 `https://api.xiaomimimo.com/v1`；`ttsModels` 包含 `mimo-v2.5-tts`；`textModels` 不含 `mimo-v2.5` 前缀；`baseUrl` 不含 `token-plan-`。
- [x] 3.2 运行 `flutter test test/tts_engine_provider_transparency_test.dart` 验证既有断言与新增断言均通过。

## 4. 文档与验证

- [x] 4.1 用 `flutter analyze lib/shell/ai_config_page.dart` 确认无新增告警。
- [x] 4.2 手工冒烟：配置页激活 MiMo 预设 → 校验名称/协议/URL/三槽位模型预填正确；保存后用 `OpenAiTtsEngine.isMimoModel('mimo-v2.5-tts', baseUrl: 'https://api.xiaomimimo.com/v1')` 识别为 true（可复用现有单测覆盖，无需单独冒烟）。
