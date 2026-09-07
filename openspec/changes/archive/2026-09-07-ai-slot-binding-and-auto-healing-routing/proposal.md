## Why

当前 AI 能力槽位绑定（Text / Multimodal / TTS / STT）采用静态映射：用户手动将供应商+模型绑定到槽位，一旦绑定的供应商凭证失效、模型下线、或供应商离线，`AiService.chat()` 调用直接抛异常，业务工具（如 Smart Disk Slimmer 的 AI 研判）立即不可用，且用户看不到结构化的失败原因。同时，当前槽位只支持单供应商绑定，无法表达优先级或备用链路。

本变更引入 **自动愈合路由（Auto-Healing Routing）** 机制，使每个能力槽位支持按优先级排列的多供应商候选链，运行时自动探测健康状态并降级切换，保证业务工具在单一供应商中断时仍能持续获得 AI 能力。

## What Changes

- **多候选槽位绑定**：每个能力槽位（text / multimodal / tts / stt）从单一 `{providerId, model}` 升级为有序候选列表 `[{providerId, model, priority}]`，用户可拖拽排列优先级。
- **运行时健康探测与自动降级**：`AiService` 在路由请求时，按优先级依次尝试候选供应商；若首选供应商连接失败或返回错误，自动尝试下一候选，并记录降级事件。
- **供应商健康状态缓存**：引入轻量级健康状态缓存（最近一次成功/失败时间戳 + 冷却窗口），避免对已知不可用的供应商反复发起无效请求。
- **路由决策透明化**：`chat()` 返回结果附带实际使用的供应商/模型信息及降级路径，业务工具可选择性展示。
- **槽位健康仪表盘**：AI 配置页的"默认能力槽位"Tab 增加每个槽位的实时健康指示（绿/黄/红），展示当前活跃供应商及最近降级事件。
- **空槽位/全部离线优雅降级**：当槽位无候选或所有候选均不可用时，返回结构化错误（`SlotUnavailableException`）而非泛型异常，业务工具可据此展示有意义的引导提示。

## Capabilities

### New Capabilities
- `ai-routing`: AI 能力路由引擎——多候选槽位解析、健康探测、自动降级与路由决策透明化

### Modified Capabilities
- `ai-configuration`: 槽位绑定数据结构从单一绑定升级为有序候选列表，配置 UI 支持多候选管理与健康状态展示

## Impact

- **`lib/services/ai_service.dart`**：`chat()` 方法重构为多候选路由逻辑，新增健康缓存与降级机制
- **`lib/services/ai_config_store.dart`**：`slotBindings` 数据结构变更为候选列表，需迁移现有单绑定配置
- **`lib/shell/ai_config_page.dart`**：槽位 Tab 重做为多候选管理 UI，增加健康状态展示
- **`ai_config.json`** 持久化格式：`defaultSlots` 字段升级，需向后兼容旧格式
- **业务工具（Smart Disk Slimmer 等）**：无需修改，但可选择性消费路由元信息以优化错误提示
