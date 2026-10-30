## Purpose

规范 IP 主库（角色卡、场景库、道具库）中由用户上传或 AI 生成的参考图片的查看、删除和 AI 生成能力，确保三个子库能力对称且一致。

## ADDED Requirements

### Requirement: 参考图全屏预览

IP 主库角色卡、场景库、道具库的所有参考图（包含 AI 生成图和用户上传图）SHALL 支持点击后全屏预览。

#### Scenario: 角色卡参考图全屏预览

- **WHEN** 用户点击角色卡中任意一张参考图缩略图
- **THEN** 系统 SHALL 以全屏对话框展示该图片原始尺寸，并提供关闭入口

#### Scenario: 道具库图片全屏预览

- **WHEN** 用户在道具编辑面板点击任意缩略图
- **THEN** 系统 SHALL 以全屏对话框展示该图片原始尺寸

#### Scenario: 场景库图片全屏预览

- **WHEN** 用户在场景编辑面板点击任意缩略图
- **THEN** 系统 SHALL 以全屏对话框展示该图片原始尺寸

### Requirement: 参考图单张删除

角色卡、场景库、道具库的参考图列表 SHALL 支持单张删除。删除操作 SHALL 要求用户确认，且 SHALL 同时删除对应磁盘文件并更新元数据。

#### Scenario: 删除角色卡参考图

- **WHEN** 用户在参考图列表选择某张图并确认删除
- **THEN** 系统 SHALL 将其从 `referenceImages` 列表移除并删除对应文件，其余图片不受影响

#### Scenario: 删除三视图

- **WHEN** 用户在角色卡删除已生成的三视图
- **THEN** 系统 SHALL 将 `turnaround.png` 从 referenceImages 移除并删除磁盘文件，其余基准参考图不受影响

### Requirement: 场景库 AI 生成图

场景库的场景编辑面板 SHALL 提供 AI 生成参考图功能，能力对齐道具库：按场景描述 prompt 调用图像模型生成，生成结果存入场景目录，用户可将其收进资产库（归类为 `scene`）。

#### Scenario: 为场景生成 AI 参考图

- **WHEN** 用户在场景编辑面板点击「生成场景图」且已填写英文 Prompt
- **THEN** 系统 SHALL 调用当前图像模型生成图片并将结果追加至场景的 referenceImages

#### Scenario: 场景图生成失败不污染现有图片

- **WHEN** AI 生成场景图时发生错误
- **THEN** 系统 SHALL 显示错误原因，既有参考图 SHALL 保持不变

### Requirement: 角色卡三视图在图片列表中可见

角色卡已生成的三视图 SHALL 在参考图列表中以独立条目展示（带「三视图」标签），与普通基准参考图共同呈现，支持预览和删除。

#### Scenario: 三视图生成后列表刷新

- **WHEN** 角色卡三视图生成成功
- **THEN** 系统 SHALL 立即在参考图列表中展示新的三视图缩略图，并标注「三视图」标签

#### Scenario: 三视图在列表中可预览

- **WHEN** 用户点击三视图缩略图
- **THEN** 系统 SHALL 以全屏对话框展示三视图原始尺寸
