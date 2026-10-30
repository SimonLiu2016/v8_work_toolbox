## 1. 导出工具类与序列化器开发

- [x] 1.1 实现分镜表导出工具类（生成包含剧集总览、场次分段、镜号、景别、运镜、画面提示词、角色台词、时长等列的 Markdown 文档）
- [x] 1.2 实现分镜表 CSV 导出序列化器（生成符合 RFC 4180 标准、带 UTF-8 BOM `\uFEFF`、单元格换行转义的工业分镜表格）
- [x] 1.3 编写分镜表导出格式的单元测试，验证 Markdown 表格排版与 CSV 转义/BOM 正确性
- [x] 1.4 实现外部剧本文件解析探测器（支持 `.md`、`.txt`、`.fountain` 文件读取，自动探测场次标记并切分为 `DramaScene`，或降级为纯文本）

## 2. 剧本工作台导入导出能力落地

- [x] 2.1 在 `screenplay_panel.dart` 顶部工具栏增加「导入剧本」按钮与防覆盖二次确认弹窗
- [x] 2.2 在 `screenplay_panel.dart` 空白态引导区增加「通道 C：导入外部剧本」卡片
- [x] 2.3 在 `screenplay_panel.dart` 顶部工具栏增加「导出剧本」操作，支持导出为文学剧本 Markdown (`.md`) 与纯文本 (`.txt`)
- [x] 2.4 集成 `FilePicker` 保存对话框与保存成功后的 SnackBar 访达定位提示

## 3. 分镜看板整集分镜表导出落地

- [x] 3.1 在 `storyboard_board.dart` 顶部操作栏新增「导出分镜表」下拉按钮（含 Markdown 与 CSV 两项选项）
- [x] 3.2 绑定导出逻辑与 `FilePicker.platform.saveFile` 保存流程，并在镜头为空时禁用该操作
- [x] 3.3 导出完成后弹出带「在访达中显示」动作的成功提示

## 4. 验证测试与本地部署

- [x] 4.1 运行 `flutter analyze` 确保无类型错误与代码警告
- [x] 4.2 运行相关测试确保回归正常
- [x] 4.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，验证已部署实例运行无误
