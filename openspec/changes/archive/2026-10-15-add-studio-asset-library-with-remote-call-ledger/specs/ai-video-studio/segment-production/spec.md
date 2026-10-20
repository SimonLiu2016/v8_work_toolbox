## MODIFIED Requirements

### Requirement: 片段媒体存放与交付兼容

系统 SHALL 将片段视频存放于 `series_library/<series-id>/episodes/<ep-id>/segments/` 下，文件名 SHALL 包含片段序号。

合成交付与剪映导出 SHALL 继续按分镜顺序消费媒体：片段产物与分镜产物同时存在时，系统 SHALL 按分镜顺序优先使用分镜级产物，缺失时使用所属片段的产物并按其时长计入时间轴。

合成交付的素材来源 SHALL  additionally 包含资产库中的视频片段：用户可从资产库选择片段加入时间线，选中片段 SHALL 按其在时间线的位置与既有产物按同一套顺序规则参与合成。该来源的加入 MUST NOT 改变既有合成与导出的顺序规则。

#### Scenario: 合成时混用片段与分镜产物
- **WHEN** 某集第 1–3 镜来自片段产物、第 4 镜为单独分镜产物
- **THEN** 系统 SHALL 在合成时按 1–4 的顺序拼接，片段产物按其在分镜序列中的位置插入，且总时长计算包含两部分

#### Scenario: 从资产库选片段进时间线
- **WHEN** 用户在合成交付时从资产库选择一个视频片段加入时间线
- **THEN** 该片段 SHALL 出现在时间线中
- **AND** 合成时 SHALL 按其位置与既有产物按同一套顺序规则消费

#### Scenario: 目录结构可直接访问
- **WHEN** 用户在 Finder 中打开某集的制作目录
- **THEN** 系统 SHALL 呈现 `frames/`、`clips/`、`audio/`、`segments/`、`exports/` 五个子目录，片段视频位于 `segments/` 中
