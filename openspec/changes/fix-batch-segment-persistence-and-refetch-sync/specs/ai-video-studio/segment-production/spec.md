## ADDED Requirements

### Requirement: 片段生成结果原子重载写回

系统在片段视频生成任务（`SegmentVideoGenTask`）完成并准备写回剧集分镜数据时，SHALL 重新从磁盘读取该剧集最新的 `episode` 状态，只更新当前片段的 `clipPath`、`status`、`degradedRefCount` 与 `submittedDurationSec` 字段后再执行保存，MUST NOT 使用任务启动时所持有的旧内存快照覆盖保存。

系统在执行剧集保存（`saveEpisode`）时 SHALL 支持文件锁或串行原子保护，避免多个并发完成的大段任务发生读写冲突。

#### Scenario: 并发大段生成互不覆盖完成状态
- **WHEN** 多个大段视频生成任务并发执行，且各自在不同时间点生成完成
- **THEN** 每个大段写回时 SHALL 重新加载磁盘最新状态并仅更新自身片段
- **AND** 先后完成的大段其 `clipPath` 与 `status = done` SHALL 均被持久化保留在 `storyboard.json` 中，无一被抹除

### Requirement: 磁盘既有成片自愈对齐

系统在读取剧集（`readEpisode`）或分镜看板初始化渲染时，SHALL 对各片段进行自愈检查：若某片段在元数据中 `clipPath` 为空，但其在磁盘对应的产物路径（如 `segments/${segment.id}.mp4`）真实存在且字节数大于 0，系统 SHALL 自动将其 `clipPath` 与 `status = done` 重新建立关联，并持久化回写至 `storyboard.json`。

#### Scenario: 历史被抹除的大段成片自动恢复
- **WHEN** 某大段因历史并发覆盖导致 `clipPath` 为空，但对应 `seg-X.mp4` 仍存在于磁盘中
- **THEN** 用户再次打开该集分镜看板时，系统 SHALL 自动检测到该磁盘文件并自愈重连
- **AND** 看板卡片立即恢复显示「片段视频已生成」与「播放预览」
