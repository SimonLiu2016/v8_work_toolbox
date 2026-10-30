## 1. 恢复 series_page.dart 中的 Prompt 预览与覆盖 UI

- [x] 1.1 在 `series_page.dart` 中恢复导入 `asset_prompt_preview_dialog.dart` 与辅助依赖
- [x] 1.2 恢复角色三视图生图操作栏中的「预览 Prompt」入口与形态系统骨架覆盖
- [x] 1.3 恢复场景全景母图与方位视角机位的「预览 Prompt」入口及底部系统提示词覆盖卡片
- [x] 1.4 恢复道具编辑栏中的「预览 Prompt」入口及底部系统提示词覆盖卡片
- [x] 1.5 确保 `_PropsTabState` 保留 `didUpdateWidget` 响应式刷新

## 2. 验证与本地打包部署

- [x] 2.1 运行单元测试与 `dart analyze` 验证代码无错误
- [x] 2.2 确保 `add-mimo-style-instruction-and-voice-config` 涉及文件完整无损
- [x] 2.3 执行 `./scripts/deploy_local.sh` 重新构建并部署本机应用
