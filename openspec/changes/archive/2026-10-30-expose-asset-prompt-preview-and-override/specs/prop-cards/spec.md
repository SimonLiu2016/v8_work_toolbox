## MODIFIED Requirements

### Requirement: 道具图生成提示词透明化与覆盖
系统 SHALL 在道具编辑界面，为道具参考图生成提供**完整 Prompt 预览与编辑**能力，并在道具卡（`PropCard`）上支持持久化保存系统资产规范词覆盖值。

`PropCard` SHALL 新增可选字段 `systemPromptOverride`，存储对 `PropPromptBuilder.propAssetRequirement` 的覆盖值。不为空时 `buildPositivePrompt` SHALL 优先采用覆盖值，为空时回退到系统默认（或 `StudioPresetStore` 中的 `prop_asset` 模板）。加载旧版 JSON 时该字段缺失视为空。

#### Scenario: 预览完整道具生图 Prompt
- **WHEN** 用户在道具编辑界面点击"生成道具图"旁的"预览 Prompt"
- **THEN** 系统 SHALL 弹出包含完整正向与负向 Prompt 的预览/编辑弹窗，用户 SHALL 能修改后点击"以此 Prompt 生成"

#### Scenario: 一次性编辑 Prompt 后生成
- **WHEN** 用户在预览弹窗中修改了 Prompt 并点击"以此 Prompt 生成"
- **THEN** 系统 SHALL 使用修改后的 Prompt 提交生成请求，此次修改 SHALL NOT 自动持久化为系统覆盖值

#### Scenario: 持久化道具图系统资产规范词覆盖
- **WHEN** 用户在道具编辑界面的"系统提示词组件"区域修改资产规范词并保存
- **THEN** 覆盖值 SHALL 写入 `PropCard.systemPromptOverride` 字段并持久化
- **AND** 后续该道具的所有图像生成均使用覆盖后的资产规范词替代系统默认值

#### Scenario: 旧版 PropCard 加载兼容
- **WHEN** 系统加载不含 `systemPromptOverride` 字段的旧版 `props.json`
- **THEN** 系统 SHALL 将该字段视为空，生图行为与旧版一致，MUST NOT 报错或丢失既有道具数据
