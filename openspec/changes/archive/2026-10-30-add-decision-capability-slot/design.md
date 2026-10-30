## Context

当前系统已有 6 个能力槽位（`text`, `multimodal`, `tts`, `stt`, `video`, `image`），并在 `AiConfigStore`、`AiConfigPage` 和 `AiService` 中形成了成熟的候选绑定、健康检测、拖拽排序与降级路由机制。
决策模型（如 DeepSeek-R1, QwQ, o1, o3-mini 等）拥有长思维链（Chain of Thought）与强化推理规划能力。在具体业务场景（如安全 Agent 渗透决策、短视频分镜结构规划、复杂问答深度反思）正式接入前，需先行在基础设施层建立统一槽位声明与管理能力。

## Goals / Non-Goals

**Goals:**
- 在 `AiConfigStore` 注册全局 `decision` 槽位，并保证对存量 `ai_config.json` 平滑迁移（缺省时自动补齐空候选列表）。
- 在 `AiConfigPage` 呈现「决策模型 (Decision / Reasoning)」槽位卡片，支持候选管理、拖拽排序与聚合健康度展示。
- 在 `AiService` 中使 `slot: 'decision'` 成为正规受支持的槽位目标，抛出标准化 `SlotUnavailableException` 或执行多候选降级探测。
- 在主流提供商快捷预设（如千问 Token Plan / 通用 API）中推荐适配的推理决策模型（如 `qwq-32b`）。

**Non-Goals:**
- 不在此变更中修改具体的业务工具（如短视频工坊或安全工具箱）业务代码去强制调用 `decision` 槽位（留待各业务按需接入）。
- 不在此变更中实现专门的思维链（`<think>`）UI 解析渲染器（属于消费端 UI 关注点）。

## Decisions

### 1. 槽位 Key 与命名
- 决策槽位标识使用小写 `decision`，对标 `text`, `multimodal`, `image`, `video`。
- UI 显示名称定为 `决策模型 (Decision / Reasoning)`，描述明示其用于“任务拆解、策略规划、深度思考与复杂研判，支持 DeepSeek-R1 / QwQ / o1 等”。
- 优势：保持与现有系统槽位命名规范一致，直观传达其作为 Agent / Planner / Reasoning 决策大脑的心智。

### 2. 向下兼容性与自动初始化
- 在 `AiConfigStore._initDefaults()` 中将 `'decision': <SlotCandidate>[]` 加入初始字典。
- 在 `_load()` 反序列化 `defaultSlots` 后，显式执行 `_slotBindings.putIfAbsent('decision', () => <SlotCandidate>[]);`，避免旧版文件读取后因缺失键而引发空安全异常。

### 3. AiService 统一路由处理
- `AiService` 现有的 `chatCompletion(slot: ...)` 已经基于 `store.slotBindings[slot]` 动态获取候选。
- 当传入 `slot: 'decision'` 且未配置任何候选时，按规范抛出结构化 `SlotUnavailableException(slotName: 'decision')`，指引用户在 AI 配置页添加决策模型候选。

## Risks / Trade-offs

- **风险**：用户若在未绑定决策模型时误调用决策功能。
  - **对策**：抛出标准异常，明确提示前往 AI 能力配置页绑定，与现有 `text` / `stt` 槽位错误表现一致。
