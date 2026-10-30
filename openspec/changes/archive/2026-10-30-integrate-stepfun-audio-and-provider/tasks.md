## 1. AI 供应商配置与预设集成

- [x] 1.1 在 `lib/shell/ai_config_page.dart` 中定义 `StepFunPreset` 常量类，配置官方 Base URL（`/v1` 与 `/step_plan/v1`）及对应的在售文本与音频模型列表
- [x] 1.2 在供应商编辑弹窗中新增 `StepFun` 预设快捷按钮，并补充“语音识别模型 (STT)”与“语音合成模型 (TTS)”输入字段与控制器
- [x] 1.3 在供应商保存逻辑中持久化 `sttModels` 与 `ttsModels`，并验证槽位候选弹窗准确联动显示

## 2. ASR 端点解析与启动前置预检

- [x] 2.1 在 `LiveTranslatorCoordinator` 中重构 `_buildAsrClient` 端点拼接逻辑，自适应支持开放平台与 Step Plan 前缀
- [x] 2.2 在 `LiveTranslatorCoordinator.start` 与 `LiveTranslatorPage._start` 中加入 Fail-Fast 前置预检，在缺少有效 StepFun ASR 客户端时立即拦截并给出明确提示

## 3. 单元测试与部署验证

- [x] 3.1 在 `test/live_translator_test.dart` 中增加 StepFun ASR 端点解析与启动预检逻辑的单元测试
- [x] 3.2 执行 `flutter test test/live_translator_test.dart` 验证全部用例通过
- [x] 3.3 执行 `./scripts/deploy_local.sh` 构建、签名并安装至本机应用，实机验证 AI 供应商配置与实时会议翻译识别流程
