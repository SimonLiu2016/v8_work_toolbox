## Context

全景母图（6272x2688）生成后保存在 `panoramas/` 物理目录，并记录在场景配置 `config.json` 的 `panorama_master_path` 中。但在场景编辑弹窗 `_SceneEditorSheet` 中，`_save()` 等保存逻辑直接调用了打开弹窗时的不可变参数 `widget.scene.copyWith(...)`，未传递 `_panoramaMasterPath` 等全景元数据，导致 `null` 覆盖写盘；且弹窗缺少关闭回调监听。

## Goals / Non-Goals

**Goals:**
- **杜绝覆写遗漏**：在 `_SceneEditorSheetState` 中建立统一场景状态工厂 `_buildCurrentScene()`，所有保存点均严格持久化全景母图及其校准参数。
- **自动找回自愈**：在 `StudioProjectManager` 增加物理文件扫描挂载逻辑，当元数据缺失但磁盘存在母图时，自动复活绑定最新母图。
- **全局状态同步**：`_openEditor` 挂接 `whenComplete(_load)`，无论何种方式关闭弹窗，外部主界面即时同步。

**Non-Goals:**
- 不修改全景切片算法与 3D 漫游视口内部渲染逻辑（已在先前版本验证完善）。

## Decisions

### 1. 场景编辑弹窗状态收拢至 `_buildCurrentScene()`
- 在 `_SceneEditorSheetState` 中抽取：
  ```dart
  SceneCard _buildCurrentScene({
    Map<String, SceneDirectionalView>? views,
    String? panoramaPath,
  }) {
    final effectiveViews = views ?? _spatialViews;
    final frontView = effectiveViews[SceneDirection.front.name];
    return widget.scene.copyWith(
      name: _name.text.trim().isEmpty ? '未命名场景' : _name.text.trim(),
      descriptionZh: _descZh.text.trim().isNotEmpty
          ? _descZh.text.trim()
          : (frontView?.descriptionZh ?? ''),
      referenceImages: List.from(_refs),
      spatialViews: Map.from(effectiveViews),
      panoramaMasterPath: panoramaPath ?? _panoramaMasterPath,
      panoramaYawOffset: _panoramaYawOffset,
      panoramaFov: _panoramaFov,
      panoramaPitchOffset: _panoramaPitchOffset,
      updatedAt: DateTime.now(),
    );
  }
  ```
- 统一替换 `_save()`、`_generateDirectionImage()`、`_generateRemainingDirectionsBatch()`、`_generatePanoramaMaster()`、`_sliceAllFromPanorama()`、`_sliceSingleDirectionFromPanorama()` 中所有的裸 `widget.scene.copyWith` 调用。

### 2. `StudioProjectManager` 增加全景母图文件自愈扫描
- 在 `StudioProjectManager` 中实现 `_healPanoramaMasterPath(String seriesId, SceneCard card)`：
  - 检查 `card.panoramaMasterPath`：若文件已存在，则正常返回；
  - 若路径为空或指向的文件不存在，则扫描 `scenePanoramasDir(seriesId, card.id)` 下的 `pano_master_*.png`；
  - 若存在文件，按最后修改时间（`lastModifiedSync`）倒序排序，将最新文件的相对路径自动回填到 `card.copyWith(panoramaMasterPath: relPath)`；
  - 在 `readScene` 与 `listScenes` 中生效。

### 3. `_openEditor` 弹窗生命周期统一刷新
- 在 `series_page.dart` 的 `_openEditor(SceneCard scene)` 尾部挂接 `.whenComplete(_load)`，确保弹窗销毁后始终重载场景列表。

## Risks / Trade-offs

- **多张历史母图的选择风险**：如果用户多次生成全景母图，自愈机制按时间戳降序选取最新的 `pano_master_*.png`，符合用户的最终意图。
