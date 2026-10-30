## 1. 供应商配置预设

- [x] 1.1 在 `lib/shell/ai_config_page.dart` 中定义 `QwenPreset` 常量类（包含名称、Token Plan 端点、通用 API 端点与推荐的文本/STT/TTS模型）
- [x] 1.2 在供应商编辑弹窗新增 `千问 (Token Plan)` 与 `千问 (通用 API)` 预设 Chip，并实现一键填入对应端点与模型列表

## 2. TTS 引擎智能适配与音色防御

- [x] 2.1 在 `lib/tools/reader/services/tts_engine.dart` 中新增 `isQwenModel` 探测方法，识别千问平台与 CosyVoice/Qwen-Audio-TTS 模型特征
- [x] 2.2 在 `OpenAiTtsEngine.synthesize` 中集成千问音色兜底防御：当目标属于千问时，若音色未指定或为 OpenAI 默认音色（`alloy` 等），自动回退为千问官方推荐音色 `longxiaochun`
- [x] 2.3 确保端点自适应：无论用户填入的 Base URL 是否带 `/compatible-mode/v1`，准确拼接 `/audio/speech` 路径

## 3. 测试覆盖与回归验证

- [x] 3.1 新增单元测试：验证 `QwenPreset` 预设填充参数（Token Plan 与通用 API 区分）
- [x] 3.2 新增单元测试：验证 `OpenAiTtsEngine` 在千问/CosyVoice 模型下的音色自动更正与 Payload 封装
- [x] 3.3 运行 AI 配置与听力练习核心测试套件，确认无任何回归

## 4. 本地构建与生效

- [x] 4.1 执行 `./scripts/deploy_local.sh` 重新构建、签名并替换本机应用，确保最新代码在当前运行实例中生效
