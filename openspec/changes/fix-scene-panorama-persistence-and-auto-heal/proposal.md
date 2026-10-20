## Why

用户在场景编辑工作台中生成 360° 全景母核后，点击“保存修改”按钮或重新点开对应场景，发现已生成好的全景母图与 3D 漫游缩略图消失不见。

经排查，该缺陷由两处状态传递疏漏导致：
1. **保存时字段丢失覆写**：`_SceneEditorSheetState._save()` 在点击“保存修改”时，直接使用弹窗打开时的旧不可变实例 `widget.scene.copyWith(...)` 组装更新对象，但未传入 `panoramaMasterPath`、`panoramaYawOffset`、`panoramaFov`、`panoramaPitchOffset`，导致它们回退至打开弹窗时的初始值（`null` / 默认值），并以 `null` 覆盖写回磁盘 `config.json`，抹除了全景元数据指针（尽管底层的物理图片文件 `panoramas/pano_master_*.png` 依然存在）；
2. **生命周期关闭刷新缺失**：`_openEditor` 的 `showModalBottomSheet` 缺少 `whenComplete(_load)` 监听，导致非常规保存退出（如点击右上角 X 或遮罩层）时外部场景卡片未能即时拉取最新状态。

## What Changes

- **统一场景状态构建器（_buildCurrentScene）**：
  在 `_SceneEditorSheetState` 中实现统一的 `_buildCurrentScene()` 构造辅助函数，收拢 `_save()`、`_generateDirectionImage()`、`_generateRemainingDirectionsBatch()` 等全部落盘点，严格封装并持久化 `panoramaMasterPath`、`panoramaYawOffset`、`panoramaFov` 与 `panoramaPitchOffset`，彻底阻断全景指针在保存时被抹除的漏洞。
- **全景母图磁盘物理文件自动自愈绑定（Auto-Healing）**：
  在 `StudioProjectManager.readScene` 与 `listScenes` 中引入自愈保护机制。当 `config.json` 中的 `panoramaMasterPath` 丢失或指定文件不存在时，系统自动扫描场景 `panoramas/` 目录；若发现存在 `pano_master_*.png` 母图物理文件，自动挂载并重新关联最新的母图路径。用户此前因保存漏洞丢失绑定的全景图将无感自动复活，无需重新消耗 API 配额生图。
- **弹窗生命周期完成回调（whenComplete）**：
  在 `series_page.dart` 的 `_openEditor` 中接入 `.whenComplete(_load)`，确保无论创作者是通过“保存修改”退出、点击右上角关闭按钮退出，还是点击背景遮罩层退出，外部场景卡片列表与“360°全景母核”徽章均立即刷新同步。

## Capabilities

### New Capabilities

*(无新增独立顶层 Capability，针对全景投影资产持久化生命周期的缺陷修复与自愈)*

### Modified Capabilities

- `ai-video-studio/scene-360-panorama-projection`: 增加全景母图元数据保存持久化防御与磁盘物理文件自动自愈连接契约。

## Impact

- **代码修改**：
  - `lib/tools/ai_video_studio/ui/series_page.dart`: 在 `_SceneEditorSheetState` 中引入 `_buildCurrentScene` 并在 `_save`、单向生图、批量生图处接入；在 `_openEditor` 中接入 `whenComplete`；
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 在 `readScene` 与 `listScenes` 中增加 `_healPanoramaMasterPath` 自愈扫描。
- **测试**：
  - `test/spherical_perspective_slicer_test.dart`: 增加场景全景母图物理文件丢失自愈与保存全字段持久化测试。
