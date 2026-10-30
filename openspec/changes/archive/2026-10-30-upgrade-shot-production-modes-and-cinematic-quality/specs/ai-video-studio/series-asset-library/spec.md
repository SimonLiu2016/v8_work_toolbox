## ADDED Requirements

### Requirement: 剧集主档案持久化默认画幅比例与分辨率预设
系统 SHALL 在连续剧 IP 主库档案（`series_profile.json`）中持久化该剧集的默认画幅比例（`defaultAspectRatio`，默认支持 `9:16`、`16:9`、`21:9`、`4:3`、`1:1`）与默认分辨率档位（`defaultResolution`，如 `2K`、`1K`、`4K`、`720P`、`1080P`）。系统 SHALL 在世界观与剧集设定面板中提供可视化选择界面供用户设置与保存，所有新建集与未指定规格的分镜 SHALL 自动继承该默认设置。

#### Scenario: 剧集设定保存默认画幅为 16:9 宽幅
- **WHEN** 用户在连续剧设定面板中将默认画幅比例切换为 16:9 横屏并保存
- **THEN** 该设置被持久化至 `series_profile.json`，当前剧集所有未单独指定比例的分镜与新创建的分镜自动以 16:9 规格推进制作
