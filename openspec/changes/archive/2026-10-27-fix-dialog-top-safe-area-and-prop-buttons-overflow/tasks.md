## 1. 修复模态弹窗 macOS 顶部安全边距

- [x] 1.1 调整 `_MediaPreviewDialog` 的 `insetPadding` 顶部边距为 52px，确保右上角操作按钮（系统播放器、在访达中显示、导出、关闭）在系统拖动盲区外可正常点击
- [x] 1.2 调整 `_PropEditorSheet` 的顶部边距或添加 `SafeArea`，确保抽屉右上角的关闭按钮避让系统拖动盲区

## 2. 优化道具卡参考图与生图操作栏布局

- [x] 2.1 将 `_PropEditorSheetState` 中的参考图操作行重构为流式 `Wrap` 布局，并合理分流生图与预览按钮，消除 `RenderFlex overflowed` 横向溢出

## 3. 验证与本地应用部署

- [x] 3.1 运行 Flutter 测试与代码静态分析，确保无语法与布局回归
- [x] 3.2 运行 `./scripts/deploy_local.sh` 编译并替换启动最新本地应用产物，完成实机验证
