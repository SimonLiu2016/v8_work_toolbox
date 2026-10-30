## MODIFIED Requirements

### Requirement: 角色资产卡与形态版本化

系统 SHALL 在 IP 主库中为每个常驻角色维护一张角色资产卡，包含：角色名称、基础生图 Prompt（正向和反向）、基准参考图与基准三视图、绑定的 TTS 音色标识符。系统 SHALL 支持为同一角色创建多个命名形态（State Variation），每个形态仅存储相对于基础 Prompt 的差异词，且每个形态 SHALL 支持持有专属的三视图产物（如 `turnaround_${variation.id}.png`）与形态参考图。

当用户在角色卡上为某一形态生成三视图时，系统 SHALL 自动将角色的默认三视图（`turnaround.png`）或默认参考图作为图生图参考底图（reference image）传递给图像生成引擎，并在提示词中添加同人脸模与五官一致性约束，以确保不同装束、不同年龄时期的角色三视图保持面部身份一致性。系统 SHALL 支持在形态三视图生成时选择标准体态比例（7~8头身）或 Q 版萌系比例（2.5头身）。

#### Scenario: 自然语言角色描述转换为标准 Prompt

- **WHEN** 用户以中文自然语言描述角色外貌并点击"生成 Prompt"
- **THEN** 系统 SHALL 调用 AI 将描述翻译为符合目标生图引擎规范的英文正向 Prompt 和反向 Prompt，并显示预览供用户确认或修改

#### Scenario: 切换角色形态触发分镜 Prompt 重组

- **WHEN** 用户在单集制作区将某角色的激活形态从"默认"切换为"战损版"
- **THEN** 系统 SHALL 将该集所有包含该角色的待生成分镜的 Prompt 自动重组，已生成的历史分镜不受影响

#### Scenario: 为子形态生成三视图时自动继承默认脸模底图

- **WHEN** 用户在角色卡「形态列表」中为「玄铁重铠」或「少年期」形态点击「生成该形态三视图」
- **THEN** 系统 SHALL 自动提取角色的基准 `turnaround.png` 文件，作为 `referenceImages` 输入图像生成适配器，生成的图像文件 SHALL 独立落盘为 `turnaround_${variation.id}.png`，不覆盖基准默认三视图

#### Scenario: 形态三视图支持独立收进资产库

- **WHEN** 用户在形态三视图缩略图上点击收进资产库
- **THEN** 系统 SHALL 将该形态三视图作为图像资产入库，并自动附加角色名、形态名称、三视图标签与当前时代题材标签

## ADDED Requirements

### Requirement: 角色形态三视图生命周期管理

系统 SHALL 在角色卡「形态列表」面板中为每个形态提供独立的三视图状态展示。当形态存在三视图时，系统 SHALL 显示三视图缩略图、点击高清大图预览、删除三视图及重新生成操作；当删除形态时，系统 SHALL 同步清理本地磁盘上对应的形态三视图文件。

#### Scenario: 预览形态专属三视图

- **WHEN** 用户点击某形态卡片上的三视图缩略图
- **THEN** 系统 SHALL 弹出高清图片预览窗口，标题显示当前角色名与形态名

#### Scenario: 删除形态时清理磁盘三视图

- **WHEN** 用户在角色卡编辑界面删除一个已生成三视图的形态
- **THEN** 系统 SHALL 在保存角色卡时同步删除磁盘上的 `turnaround_${variation.id}.png` 文件
