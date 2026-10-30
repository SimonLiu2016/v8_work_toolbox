## ADDED Requirements

### Requirement: 角色基准与形态三视图外部导入

系统 SHALL 支持为角色基准卡片及各个角色形态（CharacterVariation）从外部导入已有三视图。导入源 SHALL 至少支持本地文件系统选取（PNG/JPG/JPEG/WEBP）以及从全局资产库（AssetLibrary）中选取。

外部导入成功后，系统 SHALL 将图片复制存入该角色专属目录下（基准三视图存为 `turnaround.png`，形态三视图存为 `turnaround_var_<id>.png` 并更新形态的 `turnaroundPath`），且 MUST NOT 因原外部文件移动或删除而丢失角色三视图。

#### Scenario: 从本地文件导入角色三视图
- **WHEN** 用户在角色操作栏点击「导入三视图」并选取有效的本地图片文件
- **THEN** 系统 SHALL 将该文件复制为角色目录下的 `turnaround.png`
- **AND** 界面即时刷新显示三视图缩略图，并提供大图预览与面部截取操作

#### Scenario: 从全局资产库导入角色三视图
- **WHEN** 用户在角色操作栏点击「从资产库选择三视图」并选中一张图片
- **THEN** 系统 SHALL 复制该资产至角色目录并设为 `turnaround.png`

#### Scenario: 为角色形态导入专属三视图
- **WHEN** 用户在某角色形态卡片中点击「导入形态三视图」并选择图片
- **THEN** 系统 SHALL 将图片存入角色目录为 `turnaround_var_<id>.png`，并更新该形态的 `turnaround_path`

### Requirement: 三视图导入后面部特写智能引导

当用户成功导入角色基准三视图时，系统 SHALL 检查当前角色是否已拥有面部特写锚点（`face_anchor.png`）。若当前角色尚未配置面部特写锚点，系统 SHALL 智能弹出交互式面部裁切弹窗（FaceCropDialog），引导用户从三视图左侧截取 1:1 正脸面相锚点；若已存在面部特写锚点，系统 SHALL 保留既有面相并提示用户可通过「从三视图截取面部」按需重新截取。

#### Scenario: 无面部锚点时自动引导截取
- **WHEN** 用户为一个尚未拥有面部特写锚点的角色成功导入三视图
- **THEN** 系统自动弹出面部特写裁切弹窗，展示刚刚导入的三视图供用户圈选正脸特写

#### Scenario: 已有面部锚点时温和提示
- **WHEN** 用户为一个已有面部锚点的角色重新导入三视图
- **THEN** 系统保持既有面部锚点不变，并在界面提示三视图已更新且可按需重新截取面相
