## Why

在“编剧研讨室”完成全季规划与道具抽取后，用户点击“同步道具”或“一键沉淀至 IP 资产库”时，虽然提示同步成功，但返回“IP 资产库”后“道具”页签依然为空。

经排查，底层 `StudioProjectManager.saveProp` 仅使用 `map` 进行已有道具替换，当传入新生成的 `PropCard` 时因匹配不到 ID 而静默丢弃，导致新道具无法写入剧集元数据；同时，研讨室在同步道具后未将最新对象回传刷新，定稿时使用陈旧剧集快照覆盖也会导致道具丢失，且道具页签缺少 `didUpdateWidget` 响应式刷新。

## What Changes

- **修复 `saveProp` 为真正的 Upsert**：在 `StudioProjectManager.saveProp` 中，当道具 ID 不存在于剧集列表中时，自动将其追加至 `props` 列表末尾，而不是静默丢弃。
- **完善研讨室道具沉淀与通知机制**：
  - 在 `writers_room_dialog.dart` 中，同步道具时维护内存中新增道具的查重映射，同步完成后立即通过 `widget.onSeriesUpdated` 通知主页面更新剧集实例。
  - 在研讨室「定稿并同步至剧集库」时，基于磁盘最新读取的 `series` 进行元数据合并（`copyWith`），防止陈旧快照把已沉淀道具冲刷清空。
- **增强 IP 资产库道具页签响应式刷新**：在 `_PropsTabState` 中实现 `didUpdateWidget`，当检测到关联剧集或其道具列表变动时自动触发 `_load()` 刷新列表。

## Capabilities

### Modified Capabilities
- `prop-cards`: 规范道具资产卡持久化契约，确保通过编剧研讨室一键沉淀或 API 调用保存新道具时具备 Upsert 能力，并在 IP 资产库道具页签即时展现。

## Impact

- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 修复 `saveProp` 逻辑。
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`: 修复同步道具回传通知、定稿防覆盖。
- `lib/tools/ai_video_studio/ui/series_page.dart`: `_PropsTabState` 增加 `didUpdateWidget` 响应刷新。
