## MODIFIED Requirements

### Requirement: 角色三视图生成提示词透明化与覆盖
系统 SHALL 在角色形态三视图生成界面，提供**完整 Prompt 预览与编辑**能力，并在角色形态卡（`CharacterVariation`）上支持持久化保存系统骨架词覆盖值。

用户触发角色三视图生成前，SHALL 能查看由系统拼装的完整正向与负向提示词（含三视图布局规范、PBR 去塑料守卫、年龄阶段防漂移约束等所有系统层），并在提交前进行一次性文字修改。

`CharacterVariation` SHALL 新增可选字段 `systemPromptOverride`，存储对 `CharacterTurnaroundPrompt` 中系统骨架词（`_viewLayoutRequirement`、`_identityRequirement`、`pbrAntiPlasticGuardPositive` 等）的覆盖值。不为空时 `buildForVariation` SHALL 优先采用，为空时回退到系统默认。加载旧版 JSON 时该字段缺失视为空。

#### Scenario: 预览完整角色三视图生成 Prompt
- **WHEN** 用户在角色形态三视图生成界面点击"预览 Prompt"
- **THEN** 系统 SHALL 弹出包含完整正向与负向 Prompt 的预览/编辑弹窗，用户 SHALL 能修改后点击"以此 Prompt 生成"

#### Scenario: 一次性编辑 Prompt 后生成
- **WHEN** 用户在预览弹窗中修改了 Prompt 并点击"以此 Prompt 生成"
- **THEN** 系统 SHALL 使用修改后的 Prompt 提交生成请求，此次修改 SHALL NOT 自动持久化为系统覆盖值

#### Scenario: 持久化角色三视图系统骨架词覆盖
- **WHEN** 用户在角色形态编辑界面的"系统提示词组件"区域修改三视图骨架词并保存
- **THEN** 覆盖值 SHALL 写入 `CharacterVariation.systemPromptOverride` 字段并持久化
- **AND** 后续该形态的所有三视图生成均使用覆盖后的骨架词替代系统默认值
