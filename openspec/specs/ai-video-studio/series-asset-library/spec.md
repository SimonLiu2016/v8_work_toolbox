# series-asset-library Specification

## Purpose

三层资产体系（全局公共库 / 连续剧 IP 主库 / 单集制作区），管理角色、场景、风格预设与跨集记忆。
## Requirements
### Requirement: 三层资产体系

系统 SHALL 将资产组织为三层：全局公共库（跨剧通用）、连续剧 IP 主库（单部剧专属）、单集制作区（单集临时）。下层资产 SHALL 默认继承上层同名资产，但允许在本层覆盖。系统 SHALL 保证全局公共库中的素材（BGM、音效、风格预设）可被所有剧集项目引用，而 IP 主库和单集区的资产对其他剧集不可见。

#### Scenario: 单集制作时引用公共 BGM

- **WHEN** 用户在单集分镜编辑器中为某分镜选择背景音乐
- **THEN** 系统 SHALL 同时展示来自全局公共库的 BGM 列表和来自当前 IP 主库的专属 BGM，并在每项旁边标注来源层级

#### Scenario: 单集覆盖 IP 主库角色形态

- **WHEN** 用户在单集制作区为主角选择了非默认形态（如"战损版"）
- **THEN** 系统 SHALL 仅在该集内所有分镜中应用"战损版"形态的 Prompt 差异词，IP 主库中的角色默认形态不受影响

### Requirement: 角色资产卡与形态版本化

系统 SHALL 在 IP 主库中为每个常驻角色维护一张角色资产卡，包含：角色名称、基础生图 Prompt（正向和反向）、正面基准参考图（至少一张）、绑定的 TTS 音色标识符。系统 SHALL 支持为同一角色创建多个命名形态（State Variation），每个形态 SHALL 仅存储相对于基础 Prompt 的差异词，合并后形成完整 Prompt。系统 SHALL 在分镜生产阶段自动将当前激活形态的完整 Prompt 组装到生图请求中。

#### Scenario: 自然语言角色描述转换为标准 Prompt

- **WHEN** 用户以中文自然语言描述角色外貌并点击"生成 Prompt"
- **THEN** 系统 SHALL 调用 AI 将描述翻译为符合目标生图引擎规范的英文正向 Prompt 和反向 Prompt，并显示预览供用户确认或修改

#### Scenario: 切换角色形态触发分镜 Prompt 重组

- **WHEN** 用户在单集制作区将某角色的激活形态从"默认"切换为"战损版"
- **THEN** 系统 SHALL 将该集所有包含该角色的待生成分镜的 Prompt 自动重组，已生成的历史分镜不受影响

### Requirement: 跨集剧情记忆传递

系统 SHALL 为每个 IP 主库维护一份剧情记忆库，包含：各已完成集的剧情摘要、每集末尾的悬念钩子（Hook）文本、人物状态变化记录。当用户创建新一集时，系统 SHALL 自动将前情摘要和上集钩子注入 AI 剧本生成的上下文，用户不可见该注入内容，但可在"前情回顾"面板中查看和编辑。

#### Scenario: 新建后续集时自动注入前情上下文

- **WHEN** 用户在已有 2 集及以上历史的剧集中新建下一集
- **THEN** 系统 SHALL 在 AI 剧本生成请求中自动包含所有已完成集的摘要和最后一集的末尾钩子，AI 生成的新集剧本 SHALL 在内容上与上集结尾衔接

#### Scenario: 手动编辑前情摘要

- **WHEN** 用户在"前情回顾"面板中修改某集的剧情摘要文本
- **THEN** 系统 SHALL 在后续新建集时使用修改后的摘要文本作为上下文

### Requirement: 本地文件目录结构

系统 SHALL 将所有视频工坊数据存储在 `AppSupportDir/video_studio/` 下，目录结构 SHALL 固定为：`global_library/`（全局公共资产）、`series_library/<series-id>/`（每部剧的 IP 主库，含 `characters/`、`common_scenes/`、`series_profile.json`）、`series_library/<series-id>/episodes/<ep-id>/`（单集制作区，含 `storyboard.json`、`audio/`、`frames/`、`clips/`、`segments/`、`exports/`）。

在场景目录 `common_scenes/<scene-id>/` 中，系统 SHALL 支持 `references/`（常规与方位参考图）与 `panoramas/`（360° 等矩全景母图文件）。

`segments/` SHALL 存放片段级视频产物，文件名 SHALL 包含片段序号；`clips/` 继续存放分镜级视频产物。

#### Scenario: 新建剧集项目时目录自动创建

- **WHEN** 用户新建一部连续剧项目
- **THEN** 系统 SHALL 在 `AppSupportDir/video_studio/series_library/` 下自动创建对应目录结构，用户无需手动创建任何文件夹

#### Scenario: 通过系统文件管理器可直接访问原始素材

- **WHEN** 用户在 Finder 中打开 `AppSupportDir/video_studio/` 目录
- **THEN** 用户 SHALL 能按可预期的层级（剧集/集数/音频、帧、片段、导出）直接找到所有生成的原始素材文件

### Requirement: 场景资产卡全景母图与切片多源扩展

系统 SHALL 在 IP 主库的场景资产卡（`SceneCard`）中增加全景母图引用（`panoramaMasterPath`），并为各个空间方位的视角（`SceneDirectionalView`）支持记录生成源（`sourceType: panorama_slice | individual_ai | manual_upload`）。当使用切片引擎填充视角时，系统 SHALL 将视角图片路径自动持久化至场景配置并同步到文件系统。

#### Scenario: 场景卡持久化全景母图与切片路径
- **WHEN** 用户保存包含 360° 全景母图及切片视角的场景
- **THEN** 系统 SHALL 将全景图相对路径写入 `SceneCard` 的元数据中，后续重新打开项目时能完整恢复全景母图与各切片视角的绑定关系

