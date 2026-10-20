## ADDED Requirements

### Requirement: 角色三视图体态比例与Q版萌系模式

系统 SHALL 在角色卡三视图生成环节支持体态比例选择（标准全身比例 vs Q版萌系）。标准比例下系统 SHALL 注入成人修长头身比正向锚点，并严格在负向提示词中排他拦截 Q 版（chibi/SD）偏置；Q 版萌系模式下系统 SHALL 注入大头小身萌态正向锚点并拦截成人写实体态。系统 SHALL 支持在角色资产目录下独立保留标准三视图与 Q 版三视图产物，并在生成 Q 版三视图后支持一键创建关联的 Q 版角色形态（Variation）。

#### Scenario: 默认生成标准比例三视图
- **WHEN** 用户在角色卡「生成三视图」操作中选择「标准比例（7~8头身）」
- **THEN** 系统 SHALL 组装标准成人比例正向锚点，并在负向提示词中复合注入排他词（包括 chibi, super deformed, q-version, big head small body 等），产物落盘为 `turnaround.png` 并加入参考图列表。

#### Scenario: 生成 Q版萌系三视图并共存
- **WHEN** 用户在角色卡「生成三视图」操作中选择「Q版萌系（2.5头身）」
- **THEN** 系统 SHALL 组装大头小身萌态正向锚点并在负向中抑制写实成人比例，产物独立落盘为 `turnaround_chibi.png`，在参考图列表中标识为「Q版三视图」，与标准三视图互不覆盖。

#### Scenario: Q版三视图联动创建形态
- **WHEN** 角色成功生成 Q 版三视图且该角色尚未配置 Q 版形态
- **THEN** 系统 SHALL 支持用户一键创建以该 Q 版三视图为参考图的「Q版形态」（CharacterVariation），便于在分镜剧本中直接切换生效。

#### Scenario: 资产库入库差异化打标
- **WHEN** 用户将标准三视图或 Q 版三视图收进资产库
- **THEN** 系统 SHALL 根据文件类型自动为资产追加「标准比例」或「Q版萌系」专属标签，以便在资产选择器中精准检索。
