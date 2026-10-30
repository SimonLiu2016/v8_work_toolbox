## Purpose

管理安全测试 Agent 的自主决策循环、工具执行动态感知与渗透总结展示。

## ADDED Requirements

### Requirement: Agent 执行进度与动态轮次展示
系统 SHALL 根据 Agent 当前所处状态（规划中、正在执行某工具、等待审批、已完成、失败）动态呈现准确的轮次与执行状态，禁止以可用工具总数硬编码作为步骤分母。

#### Scenario: Agent 正在调用工具
- **WHEN** Agent 决策调用某一工具（如 `run_subfinder`）并启动底层探测
- **THEN** 界面状态显示为“运行中”，并展示当前正在执行的工具名称与动态加载指示

#### Scenario: Agent 完成执行
- **WHEN** Agent 达成目标或迭代收敛结束
- **THEN** 界面状态显示为“已完成”，并标注“共执行 N 步”或“已完成”，不再显示误导性的“1/9”

### Requirement: 完整的 Agent 渗透总结呈现
系统 SHALL 在 Agent 决策循环收敛并给出最终分析建议后，将大模型的最终分析报告完整呈现给用户。

#### Scenario: 呈现最终渗透分析
- **WHEN** Agent 结束全部工具调用并给出最终回答
- **THEN** 界面展示「Agent 综合分析与渗透建议」区域，渲染结构化的分析结论
