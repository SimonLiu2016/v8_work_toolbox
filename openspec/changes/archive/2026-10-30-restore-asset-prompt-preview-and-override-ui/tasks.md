## 1. 恢复依赖导入与场景编辑 UI

- [x] 1.1 在 `lib/tools/ai_video_studio/ui/series_page.dart` 中恢复导入 `asset_prompt_preview_dialog.dart`
- [x] 1.2 在 `_SceneEditorSheetState` 中恢复 `_systemPromptOverride` 与 `_panoramaSystemPromptOverride` 状态控制器、初始化、销毁与保存逻辑
- [x] 1.3 在 `_SceneEditorSheetState` 中恢复 `_previewPanoramaPrompt` 和 `_previewDirectionPrompt` 方法与生图联动
- [x] 1.4 在场景全景母核操作栏与方位机位操作栏添加“预览 Prompt”按钮
- [x] 1.5 在场景编辑面板底部恢复“系统提示词组件与覆盖 (高级)”折叠面板

## 2. 恢复道具编辑 UI 与系统覆盖

- [x] 2.1 在 `_PropEditorSheetState` 中恢复 `_systemPromptOverride` 控制器、初始化、销毁与保存逻辑
- [x] 2.2 在 `_PropEditorSheetState` 中恢复 `_previewPrompt` 方法与生图联动
- [x] 2.3 在道具编辑底部操作栏中恢复“预览 Prompt”按钮
- [x] 2.4 在道具编辑面板底部恢复“系统提示词组件与覆盖 (高级)”折叠面板

## 3. 恢复角色三视图预览入口

- [x] 3.1 在 `_CharacterCardState` / 形态编辑区恢复三视图生图的“预览 Prompt”入口及覆盖配置

## 4. 验证与工程构建部署

- [x] 4.1 运行相关测试确保全量通过
- [x] 4.2 运行 `flutter analyze` 确保无静态语法分析错误
- [x] 4.3 运行 `./scripts/deploy_local.sh` 编译并替换启动最新本地应用
