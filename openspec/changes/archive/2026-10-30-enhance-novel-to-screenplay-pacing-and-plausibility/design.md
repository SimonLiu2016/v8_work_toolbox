## Context

当前工程中，AI 视频工坊的提示词存在局部硬编码现象：`StudioPresetStore` 虽具备基础的 `StudioPromptTemplate` 集合，但此前仅有 `director_breakdown_5d` 接入了动态读取，而 `novelDramaChapterAdaptation`、`screenplayGeneration`、`directorAuditAutoFix` 等大模型任务仍直接使用静态常量。此外，剧本生成逻辑未对“公共空间与社会生态”做结构化约束，拆镜引擎对 9:16 竖屏的工业化约束（景别比例、同框人数、字幕留白）较为分散。

本设计旨在建立统一的**提示词中枢注册与装配机制**，并横向赋能策划、剧本、分镜与质检全链路。

## Goals / Non-Goals

**Goals:**
- **全链路 Prompt 解耦与可视化可配置**：所有与大模型交互的 System Prompt 均在 `StudioPresetStore` 注册为模板，支持动态插槽变量解析、界面自由编辑、一键恢复与 JSON 导出/导入。
- **环境生态与社会常识推演引擎**：在小说转剧本中嵌入公私空间研判法则，强制推导公共场所 NPC 反应或自动修正隐秘事发地点，消除“横尸闹市无人理”的荒诞穿帮。
- **竖屏短剧节拍器机制**：在剧本中硬约束黄金 3 秒开局、15 秒情绪反转阶梯、心理描写具象动作化与集尾极限断章。
- **竖屏 9:16 工业拆镜与提示词组装**：单镜头人物 ≤ 3、中近景特写偏好、底部 1/5 字幕安全区、正向美学锚点与负向防崩坏词库。
- **编剧研讨室（Writers' Room）宏观共创**：提供小说全景主线提取、必留/可删/可改情节分类与人机协商式分集大纲调整。
- **门禁扩展（C10~C11）**：自动化检测环境常识闭环与短剧高压节拍。

**Non-Goals:**
- 不改变底层视频生成后端的原生通信协议（如 Agnes、Kling 等）。
- 不引入重型本地模型训练管道（如本地 LoRA 训练），聚焦于上游剧作决策、分镜结构化与提示词工程。

## Decisions

### 1. 集中式提示词注册与动态插槽解析（Prompt Hub & Slot Engine）
- **架构方案**：在 `StudioPromptTemplate` 中为各流程步骤分配规范化 `id`。在 `AiConstraintEngine` 中实现统一的 `resolveSystemPrompt(StudioAiTask, {Map<String, String>? slots})`。
- **插槽变量语法**：统一采用 Mustache 风格双花括号 `{{variable_name}}`。装配引擎自动将当前上下文（如 `series_name`、`worldview`、`characters`、`scenes`、`pacing_rules` 等）注入插槽。若某个插槽未传参，则安全保留空串或优雅降级。
- **备选方案对比**：
  - *方案 A（在每个服务分散处理字符串拼接）*：难以维护，无法集中在设置界面统一呈现和编辑。
  - *方案 B（集中式模板注册中心，选中）*：单一数据源（Single Source of Truth），持久化于 `prompt_templates.json`，支持出厂自愈与热更新。

### 2. 子规则模块化复合装配（Composable Sub-rules）
- **设计决策**：剧本主提示词 `screenplay_novel_adapt` 不把“环境常识推演”和“短剧节拍法则”写死为一段大长文本，而是将 `screenplay_plausibility_rules` 与 `screenplay_beat_pacing_rules` 作为独立的子模板注册。
- **优势**：用户如果只想微调“短剧卡点断章偏好”或“特定门派的 NPC 反应”，只需修改对应的小模板，无需承担改坏整个 JSON Schema 结构的风险。

### 3. 编剧研讨室（Writers' Room）长文切片与多轮共创会话
- **设计决策**：在 `novel-import` 与 `IdeaIncubatorPanel` 中引入全书分析模式。对于几十万字的小说，利用大模型上下文窗口或章节抽样提炼，生成《全书核心脉络表》与《必留/可删/可改清单》。
- **交互形式**：在剧集策划页面引入抽屉式或弹窗式“编剧对话助手”，用户输入调整指令（如“第 3 集冲突提前”），AI 返回增量修改后的分集表。

### 4. 门禁质检（C10/C11）轻量规则与启发式正则/VLM双通道
- **设计决策**：
  - C10（环境常识）：检查公共空间（场景包含“街/市/堂/坊/广场”）发生异常词（“死/杀/倒地/重伤/拔刀”）时，动作描述是否包含群众反应词（“围观/惊呼/驻足/避让/议论/官兵/捕快”），若无则报警。
  - C11（黄金3秒与断章）：首镜头必须包含动作动词；尾镜头必须包含悬念/未完结标记，不得为“转身离去回房入睡”等平淡终止语。

## Risks / Trade-offs

- **[Risk] 用户自定义修改 Prompt 可能破坏 JSON 输出格式导致解析失败**
  → **Mitigation**: 保持 `_commonOutputRules` 和 JSON Schema 校验为系统底层硬防护（作为不可动摇的 Wrapper 尾缀追加），用户可配置区域专注于“导演业务规则、视听语法、节拍偏好与动作描述要求”，且在配置界面提供“一键测试运行”与“恢复默认”。
- **[Risk] 长篇小说一次性投喂超出大模型 Token 限制**
  → **Mitigation**: 编剧研讨室支持按已入库的“章节目录索引与摘要”进行分层提炼；超长文本自动按卷/篇章聚合，避免单次超限。
- **[Risk] 提示词模板版本迭代与旧版配置冲突**
  → **Mitigation**: `StudioPresetStore._loadTemplates` 已具备强大的版本自愈能力，加载本地 `prompt_templates.json` 时比对内置模板清单，自动补全缺失的新模板项，同时保留用户的已有覆盖项。
