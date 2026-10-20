## 1. 大段生成并发原子重载、保存锁与历史成片自愈重连

- [x] 1.1 在 `StudioProjectManager` 中针对同一集引入序列化异步写入链（`_writeChains`），确保并发调用 `saveEpisode` 时互斥串行化
- [x] 1.2 重构 `SegmentVideoGenTask.run`：在视频生成完成或取消后，重新调用 `manager.readEpisode(seriesId, episodeId)` 读取磁盘最新状态，仅更新本 `segmentId` 对应的大段状态后再保存，杜绝旧快照覆盖
- [x] 1.3 在 `StudioProjectManager.readEpisode` 与分镜看板加载时增加磁盘成片自愈重连检查，自动找回并恢复磁盘上已存在但元数据丢失的 `seg-X.mp4`

## 2. 重新取回全链路剧集回写与分镜看板刷新

- [x] 2.1 将 `VideoTaskRecovery._writeBack` 开放为公共接口，并在执行回写时同步采用最新状态重载与原子保存
- [x] 2.2 改造 `_CloudTaskTile._refetch` 与 `_refetch` 逻辑：下载成功后自动调用 `VideoTaskRecovery.writeBack` 将视频路径写入 `storyboard.json`，并透传通知分镜看板触发 `_reload()` 刷新视图

## 3. 剧本工作台多集切换 FormField 响应式渲染修复

- [x] 3.1 在 `ScreenplayPanel` 中为场次列表及各 `_buildSceneCard` 绑定带有 `episode.id` 与 `scene.id` 的唯一 `Key`
- [x] 3.2 验证第 1 集与第 2 集在非空剧本状态下拉切换时表单与节拍文本实时更新

## 4. 任务队列调用快照全量留痕与 Agnes 试炼场直达

- [x] 4.1 在 `VideoTaskLedgerEntry` 中增加结构化 `requestSnapshot` 字段，并在生成请求提交前完整捕获调用参数与参考图绝对路径
- [x] 4.2 在 `PlaygroundStore` / `PlaygroundPage` 中实现外部调用草稿（`PlaygroundDraft`）的写入、消费与输入预填支持
- [x] 4.3 在任务抽屉卡片（`_CloudTaskTile` 及相关任务行）增加「在试炼场调试」动作入口，支持一键调起试炼场并载入草稿

## 5. 资产库响应式广播与入库体验强化

- [x] 5.1 在 `AssetLibrary` 中增加 `StreamController<List<StudioAsset>>.broadcast()` 事件流，并在 `_persist()` 与 `addAsset` 完成后触发广播
- [x] 5.2 改造 `AssetLibraryPage`：在 `initState` 中监听 `AssetLibrary.instance.stream`，后台有资产增删时自动触发 `setState` 刷新
- [x] 5.3 优化分镜与大段入库时的名称生成（语义化剧集/集号/大段信息），并在无 FFmpeg 首帧封面时回退使用代表性参考图作为海报，避免纯黑卡片

## 6. 验证与本地应用部署

- [x] 6.1 编写/更新单元测试，验证并发大段保存互不覆盖、成片自愈恢复、重新取回写回以及试炼场草稿桥接
- [x] 6.2 运行静态代码检查与测试套件（`flutter analyze` 与 `flutter test`）
- [x] 6.3 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机应用
