## 1. 统一场景编辑持久化与状态守卫

- [x] 1.1 在 `_SceneEditorSheetState` 中实现 `_buildCurrentScene()` 统一状态工厂，完整封装 `panoramaMasterPath`、`panoramaYawOffset`、`panoramaFov` 与 `panoramaPitchOffset`
- [x] 1.2 重构 `_save()`、`_generateDirectionImage()`、`_generateRemainingDirectionsBatch()` 等全部落盘点，杜绝遗漏字段导致覆写清空
- [x] 1.3 在 `series_page.dart` 的 `_openEditor` 中添加 `.whenComplete(_load)`，保证弹窗关闭后场景列表与全景徽章即时同步

## 2. 全景母图物理文件自动自愈机制（Auto-Healing）

- [x] 2.1 在 `StudioProjectManager` 中实现 `_healPanoramaMasterPath`，当元数据缺失时自动扫描场景 `panoramas/` 目录恢复最新物理母图
- [x] 2.2 在 `readScene` 与 `listScenes` 中接入自愈扫描，使此前已生成的全景图无感自动复活

## 3. 验证与工程构建部署

- [x] 3.1 编写单元测试验证全景母图物理文件自动自愈挂载逻辑与完整字段保存持久化
- [x] 3.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证点击“保存修改”及反复开闭弹窗后全景图长存不灭
