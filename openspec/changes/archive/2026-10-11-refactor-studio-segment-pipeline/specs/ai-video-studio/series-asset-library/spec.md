## MODIFIED Requirements

### Requirement: 本地文件目录结构

系统 SHALL 将所有视频工坊数据存储在 `AppSupportDir/video_studio/` 下，目录结构 SHALL 固定为：`global_library/`（全局公共资产）、`series_library/<series-id>/`（每部剧的 IP 主库，含 `characters/`、`common_scenes/`、`series_profile.json`）、`series_library/<series-id>/episodes/<ep-id>/`（单集制作区，含 `storyboard.json`、`audio/`、`frames/`、`clips/`、`segments/`、`exports/`）。

`segments/` SHALL 存放片段级视频产物，文件名 SHALL 包含片段序号；`clips/` 继续存放分镜级视频产物。

#### Scenario: 新建剧集项目时目录自动创建

- **WHEN** 用户新建一部连续剧项目
- **THEN** 系统 SHALL 在 `AppSupportDir/video_studio/series_library/` 下自动创建对应目录结构，用户无需手动创建任何文件夹

#### Scenario: 通过系统文件管理器可直接访问原始素材

- **WHEN** 用户在 Finder 中打开 `AppSupportDir/video_studio/` 目录
- **THEN** 用户 SHALL 能按可预期的层级（剧集/集数/音频、帧、片段、导出）直接找到所有生成的原始素材文件
