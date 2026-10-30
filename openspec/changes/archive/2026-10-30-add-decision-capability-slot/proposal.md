## Why

现代大模型生态逐步细分出擅长长思维链（Chain-of-Thought）、任务规划与深度推理的“决策/推理模型”（如 DeepSeek-R1、OpenAI o1/o3-mini、Qwen QwQ、Claude 3.7 Thinking 等）。系统现有的全局能力槽位仅覆盖常规文本、视觉多模态、语音（TTS/STT）与生图生视频。为了在底层 AI 基础设施中提前就绪决策规划能力，需要新增专用的全局「决策模型」能力槽位（`decision`），使用户能够集中管理、配置并路由决策推理类模型。

## What Changes

- **新增决策模型能力槽位 (`decision`)**：在 `AiConfigStore` 默认全局槽位映射中增加 `decision` 槽位，支持独立的多候选（Provider + Model）绑定、优先级排序、降级路由与健康状态跟踪。
- **配置持久化与向下兼容迁移**：当加载缺少 `decision` 键的历史 `ai_config.json` 时，自动补齐空的决策槽位候选列表，防止运行时空指针或解析失败。
- **AI 能力配置 UI 扩展**：在「全局能力槽位绑定」界面中新增决策模型卡片（含文案说明、候选管理、拖拽排序与独立健康度显示）。
- **供应商预设支持决策模型**：在千问等内置快捷预设中支持预填推荐的决策/推理模型候选（例如 `qwq-32b`）。
- **统一服务层路由支持**：`AiService` 的统一路由接口支持指定 `slot: 'decision'`，并具备健全的无可用候选异常提示及降级兜底机制。

## Capabilities

### New Capabilities
<!-- 无全新的独立能力规范文件 -->

### Modified Capabilities
- `ai-configuration`: 在全局能力槽位集合中增加 `decision`（决策/推理模型）槽位规范，定义其候选绑定、健康检查、历史配置自动补齐与路由调用行为。

## Impact

- **Affected code**:
  - `lib/services/ai_config_store.dart`: 槽位默认结构、加载与迁移逻辑
  - `lib/shell/ai_config_page.dart`: UI 槽位展示列表、预设配置逻辑
  - `lib/services/ai_service.dart`: 槽位可用性校验与调用路由
  - `test/`: 增加对应的单元测试验证持久化与槽位路由
- **APIs/Dependencies**: 无外部依赖破坏性变动，向下完全兼容既有配置文件。
