## MODIFIED Requirements

### Requirement: 场景生图提示词透明化与覆盖
系统 SHALL 在场景资产卡编辑界面，为方位视角生成与 360° 全景母图生成提供**完整 Prompt 预览与编辑**能力，并支持持久化保存系统提示词组件覆盖值。

用户在触发任意场景生图操作前，SHALL 能看到由系统拼装完成的正向与负向完整 Prompt（包括所有系统注入层：空镜头锁、时代环境锚点、风格锁、全景专用约束头尾等）并在提交前进行文字修改。此次修改仅对当次生成有效（一次性覆盖），不自动持久化。

场景资产卡 SHALL 新增可选的系统提示词组件覆盖字段：
- 方位视角生图：`systemPromptOverride`（覆盖系统空镜环境前导词，即 `sceneEnvironmentRequirement` 与 `emptyHeadLock`/`emptyTailLock`）
- 全景母图生图：`panoramaSystemPromptOverride`（覆盖全景专用头尾锚 `panoHead`/`panoTail`）

以上字段不为空时，对应的 `ScenePromptBuilder.buildPositivePrompt` 与 `buildPanoramaPrompt` SHALL 优先使用覆盖值替换对应默认常量；为空时回退到系统默认。覆盖值 SHALL 随场景卡持久化到 `scenes.json`，且加载旧版无该字段的文件时 SHALL 等价为空（不报错）。

场景编辑界面 SHALL 提供可折叠的"系统提示词组件"区域，展示各组件当前实际值（系统默认或用户覆盖），并允许用户直接编辑并保存覆盖值。

#### Scenario: 预览完整场景方位生图 Prompt
- **WHEN** 用户在场景编辑界面点击方位视角的"生成图像"按钮旁的"预览 Prompt"
- **THEN** 系统 SHALL 弹出包含已组装完整正向 Prompt 与负向 Prompt 的预览/编辑弹窗
- **AND** 用户 SHALL 能直接在弹窗中修改 Prompt 文本，点击"以此 Prompt 生成"提交此次修改后的版本

#### Scenario: 预览完整场景全景母图 Prompt
- **WHEN** 用户在场景编辑界面点击"生成 360° 全景母图"旁的"预览 Prompt"
- **THEN** 系统 SHALL 展示包含全景专用头尾锚、时代环境锚点、风格词与用户描述的完整组装 Prompt

#### Scenario: 持久化覆盖场景生图系统前导词
- **WHEN** 用户在场景编辑界面的"系统提示词组件"区域修改空镜环境前导词并保存
- **THEN** 覆盖值 SHALL 写入场景卡的 `systemPromptOverride` 字段并持久化
- **AND** 后续该场景的所有方位视角生图均使用覆盖后的前导词替代系统默认值

#### Scenario: 全景母图 Prompt 组件场景类型感知
- **WHEN** 场景描述内容属于非现实建筑空间（如"意识空间"、"虚空"、"意象场景"等），用户触发全景母图生成
- **THEN** 用户 SHALL 能通过 `panoramaSystemPromptOverride` 替换强调"建筑空间感"的默认全景头尾锚，以匹配非写实场景类型的提示词约束

---

## MODIFIED Requirements

### Requirement: 角色三视图生成提示词透明化与覆盖
系统 SHALL 在角色形态三视图生成界面，提供**完整 Prompt 预览与编辑**能力，并在角色形态卡（`CharacterVariation`）上支持持久化保存系统骨架词覆盖值。

用户触发角色三视图生成前，SHALL 能查看由系统拼装的完整正向与负向提示词（含三视图布局规范、PBR 去塑料守卫、年龄阶段防漂移约束等所有系统层），并在提交前进行一次性文字修改。

`CharacterVariation` SHALL 新增可选字段 `systemPromptOverride`，存储对 `CharacterTurnaroundPrompt` 中系统骨架词（`_viewLayoutRequirement`、`_identityRequirement`、`pbrAntiPlasticGuardPositive` 等）的覆盖值。不为空时 `buildForVariation` SHALL 优先采用，为空时回退到系统默认。加载旧版 JSON 时该字段缺失视为空。

#### Scenario: 预览完整角色三视图生成 Prompt
- **WHEN** 用户在角色形态三视图生成界面点击"预览 Prompt"
- **THEN** 系统 SHALL 弹出包含完整正向与负向 Prompt 的预览/编辑弹窗，用户 SHALL 能修改后点击"以此 Prompt 生成"

#### Scenario: 持久化角色三视图系统骨架词覆盖
- **WHEN** 用户在角色形态编辑界面的"系统提示词组件"区域修改三视图骨架词并保存
- **THEN** 覆盖值 SHALL 写入 `CharacterVariation.systemPromptOverride` 字段并持久化

---

## MODIFIED Requirements

### Requirement: 道具图生成提示词透明化与覆盖
系统 SHALL 在道具编辑界面，为道具参考图生成提供**完整 Prompt 预览与编辑**能力，并在道具卡（`PropCard`）上支持持久化保存系统资产规范词覆盖值。

`PropCard` SHALL 新增可选字段 `systemPromptOverride`，存储对 `PropPromptBuilder.propAssetRequirement` 的覆盖值。不为空时 `buildPositivePrompt` SHALL 优先采用覆盖值，为空时回退到系统默认（或 `StudioPresetStore` 中的 `prop_asset` 模板）。加载旧版 JSON 时该字段缺失视为空。

#### Scenario: 预览完整道具生图 Prompt
- **WHEN** 用户在道具编辑界面点击"生成道具图"旁的"预览 Prompt"
- **THEN** 系统 SHALL 弹出包含完整正向与负向 Prompt 的预览/编辑弹窗

#### Scenario: 持久化道具图系统资产规范词覆盖
- **WHEN** 用户在道具编辑界面的"系统提示词组件"区域修改资产规范词并保存
- **THEN** 覆盖值 SHALL 写入 `PropCard.systemPromptOverride` 字段并持久化
