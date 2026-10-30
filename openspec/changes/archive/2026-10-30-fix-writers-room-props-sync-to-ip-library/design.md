## Context

当前剧集项目的道具元数据保存在 `StudioSeries.props` 中，其持久化文件为 `series_profile.json`。
在编剧研讨室（`WritersRoomDialog`）与原著全案抽取（`syncMasterExtractionToIpLibrary`）中，提取出的道具会以新建 `PropCard` 形式调用 `StudioProjectManager.saveProp` 沉淀至 IP 资产库。但由于 `saveProp` 内部使用 `.map()` 仅进行 ID 匹配替换，导致新道具被静默丢弃。同时前端存在快照覆盖与响应监听缺失问题。

## Goals / Non-Goals

**Goals:**
- 将 `StudioProjectManager.saveProp` 改造为严格的 Upsert（更新已存在，追加不存在），确保无论是单件道具保存、批量沉淀还是全案抽取，新道具均能准确持久化进 `StudioSeries.props`。
- 在 `writers_room_dialog.dart` 中建立完备的去重映射、定稿防快照覆盖机制，并在道具沉淀完成后立即回调 `widget.onSeriesUpdated`。
- 在 `_PropsTabState`（IP 资产库道具页签）增加 `didUpdateWidget` 生命周期监听，在剧集元数据或道具列表发生变动时自适应重载。

**Non-Goals:**
- 不改变 `PropCard` 数据结构及磁盘图片存储路径（`props/<propId>/`）。
- 不重构角色卡（Character）和场景库（Scene）现有的独立文件夹配置存储模式。

## Decisions

### 1. `saveProp` 改造为 Upsert 语义
- **方案**:
  ```dart
  final index = series.props.indexWhere((p) => p.id == card.id);
  final List<PropCard> props;
  if (index >= 0) {
    props = List<PropCard>.from(series.props);
    props[index] = card;
  } else {
    props = [...series.props, card];
  }
  await saveSeries(series.copyWith(props: props));
  ```
- **考量与对比**:
  - 对比仅在 `createProp` 中追加：若只让 `createProp` 负责新建，所有外部调用（如批量抽取、研讨室同步）都必须改写为先判断是否存在再调用不同方法，侵入性大。
  - 直接将 `saveProp` 升级为 Upsert，既向下兼容所有已有调用，又一举修复研讨室同步和原著全案抽取两处相同 Bug。

### 2. 研讨室道具沉淀闭环与防覆写
- **去重维护**: 在 `_syncPropsToIpLibrary` 循环中，新建道具后即刻加入 `existingByName[key] = newCard`，避免抽取结果中存在同名道具时产生多余重复条目。
- **状态通知**: 批量写入完成后，从 `_manager.readSeries(seriesId)` 读取最新对象并调用 `widget.onSeriesUpdated(latest)`。
- **定稿防覆写**: `_applyBeatsToProject` 在序列化第 1 季大纲与更新工程名称时，优先取 `_manager.readSeries(seriesId) ?? widget.series` 进行 `copyWith`，确保此前刚刚沉淀的道具列表不会被弹窗打开时的旧 `widget.series` 冲洗为空。

### 3. IP 资产库道具页签主动监听 (`didUpdateWidget`)
- 在 `_PropsTabState` 中重写 `didUpdateWidget`，比对 `widget.series.id`、`widget.series.updatedAt` 或 `widget.series.props`，变动时自动触发 `_load()`，无需用户手动切换或重进页面。

## Risks / Trade-offs

- **[并发写入竞争]** → 研讨室道具批量同步时在循环中多次调用 `saveProp`，通过 `_writeJsonAtomic` 原子写与每次重新 `readSeries` 保证一致性；也可在循环末尾按需批量保存一次，但保持逐条 upsert 语义能最大限度利用既有单项保存逻辑。
