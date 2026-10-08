## ADDED Requirements

### Requirement: AI 生成素材的本地存储路径集成

系统 SHALL 支持将通过视频下载器下载的视频文件，按用户选择，存入 `AppSupportDir/video_studio/` 的指定剧集单集目录（`series_library/<series-id>/episodes/<ep-id>/frames/`），以便直接作为 AI 短视频工坊中对应分镜的参考素材或替代视频片段使用。此功能为可选操作，默认存储路径不变。

#### Scenario: 下载视频时选择保存至剧集素材目录

- **WHEN** 用户在视频下载器中完成视频下载，且当前有活跃的 AI 视频工坊剧集项目
- **THEN** 系统 SHALL 在保存路径选项中提供"保存至 [当前剧集名称] 素材目录"的快捷选项

#### Scenario: 跨工具素材引用不影响原有下载路径

- **WHEN** 用户选择将下载视频保存至剧集素材目录
- **THEN** 系统 SHALL 将文件复制（而非移动）至目标目录，原下载目录中的文件 SHALL 不受影响
