## 1. 修复底层道具持久化 (StudioProjectManager)

- [x] 1.1 在 `StudioProjectManager.saveProp` 中实现 Upsert 逻辑（已存在则替换，不存在则追加至 `series.props`）
- [x] 1.2 校验 `syncMasterExtractionToIpLibrary` 中的原著抽取道具保存行为，确保正常沉淀

## 2. 增强编剧研讨室道具沉淀与通知闭环 (WritersRoomDialog)

- [x] 2.1 在 `_syncPropsToIpLibrary` 循环中即时维护 `existingByName` 字典，并在同步完成后回调 `widget.onSeriesUpdated`
- [x] 2.2 在 `_applyBeatsToProject` 定稿时读取磁盘最新剧集快照进行 `copyWith`，防止旧快照冲刷覆盖已沉淀道具

## 3. 增强 IP 资产库道具页签响应式刷新 (SeriesPage)

- [x] 3.1 在 `_PropsTabState` 中实现 `didUpdateWidget` 生命周期监听，在剧集实例或道具数据更新时自动调用 `_load()`

## 4. 验证与本地打包部署

- [x] 4.1 执行自动化测试与 Dart 分析检查代码完整性
- [x] 4.2 执行 `./scripts/deploy_local.sh` 重新构建、签名并部署本机应用
