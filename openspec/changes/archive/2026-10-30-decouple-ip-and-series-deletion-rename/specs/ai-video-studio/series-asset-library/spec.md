## MODIFIED Requirements

### Requirement: 三层资产体系

系统 SHALL 将资产组织为三层：全局公共库（跨剧通用）、IP 主库（常驻企划专属，含角色卡、场景库、道具、世界观）、单集制作区（单集具体剧本、分镜与音视频生成产物）。IP 主库作为长周期数字资产，其生命周期 SHALL 独立于具体的剧集制作工程。单集制作区中的剧本与分镜被删除或重置时，关联的 IP 主库（角色卡、场景卡、道具卡与世界观设定）及全局资产库（图片、视频片段）SHALL 完好保留不受影响，且可被新剧集项目继续挂载复用。

#### Scenario: 单集制作时引用公共 BGM

- **WHEN** 用户在单集分镜编辑器中为某分镜选择背景音乐
- **THEN** 系统 SHALL 同时展示来自全局公共库的 BGM 列表和来自当前 IP 主库的专属 BGM，并在每项旁边标注来源层级

#### Scenario: 单集覆盖 IP 主库角色形态

- **WHEN** 用户在单集制作区为主角选择了非默认形态（如"战损版"）
- **THEN** 系统 SHALL 仅在该集内所有分镜中应用"战损版"形态的 Prompt 差异词，IP 主库中的角色默认形态不受影响

#### Scenario: 剧集制作清除时保留 IP 主库资产

- **WHEN** 用户删除某剧集或清空制作内容
- **THEN** 系统 SHALL 仅销毁该剧集的单集分镜、剧本及音视频媒体，而该剧集所关联的 IP 主库角色卡、场景卡与道具资产 SHALL 完整保留在 IP 主库中供后续复用

### Requirement: 本地文件目录结构

系统 SHALL 将所有视频工坊数据存储在 `AppSupportDir/video_studio/` 下，目录结构 SHALL 保证 IP 资产层与单集制作层物理隔离：`global_library/`（全局公共资产）、`series_library/<series-id>/`（剧集制作与 IP 映射区，含 `characters/`、`common_scenes/`、`series_profile.json`）、`series_library/<series-id>/episodes/<ep-id>/`（单集制作区，含 `storyboard.json`、`audio/`、`frames/`、`clips/`、`segments/`、`exports/`）。

在场景目录 `common_scenes/<scene-id>/` 中，系统 SHALL 支持 `references/`（常规与方位参考图）与 `panoramas/`（360° 等矩全景母图文件）。

`segments/` SHALL 存放片段级视频产物，文件名 SHALL 包含片段序号；`clips/` 继续存放分镜级视频产物。在执行剧集删除或分集清除时，系统 SHALL 仅定向删除 `episodes/` 及其子目录，严禁递归删除 `characters/` 与 `common_scenes/`。

#### Scenario: 新建剧集项目时目录自动创建

- **WHEN** 用户新建一部连续剧项目
- **THEN** 系统 SHALL 在 `AppSupportDir/video_studio/series_library/` 下自动创建对应目录结构，用户无需手动创建任何文件夹

#### Scenario: 通过系统文件管理器可直接访问原始素材

- **WHEN** 用户在 Finder 中打开 `AppSupportDir/video_studio/` 目录
- **THEN** 用户 SHALL 能按可预期的层级（剧集/集数/音频、帧、片段、导出）直接找到所有生成的原始素材文件
