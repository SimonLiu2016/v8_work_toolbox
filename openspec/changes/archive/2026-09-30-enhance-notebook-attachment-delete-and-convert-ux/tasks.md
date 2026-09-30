## 1. 附件删除功能

- [x] 1.1 在 `attachment_block_component.dart` 操作栏中增加删除按钮与红色警示图标
- [x] 1.2 实现 `_confirmDelete(BuildContext)` 确认对话框（防止误触）
- [x] 1.3 提交事务从 `EditorState` 中删除该 Block 节点
- [x] 1.4 调用 `NoteStore.deleteAttachment(attId)` 级联清理 SQLite 数据库记录和磁盘物理文件

## 2. 转换交互与正文插入

- [x] 2.1 改造 `ConvertDialog`：增加转换完成成功状态视图，展示生成文件名、大小与完整物理路径
- [x] 2.2 在完成视图中提供「在访达中显示」与「打开文件」快捷动作
- [x] 2.3 `ConvertDialog` 支持回调返回新增的 `Attachment` 对象
- [x] 2.4 在 `attachment_block_component.dart` 接收转换完成回调，自动在当前附件节点后插入新附件节点

## 3. 验证与部署

- [x] 3.1 编写/更新 Widget 测试验证附件删除与转换回调
- [x] 3.2 运行 `flutter analyze` 确保 0 error 0 warning
- [x] 3.3 运行相关测试套件确保测试全绿
- [x] 3.4 执行 `./scripts/deploy_local.sh` 编译并本地部署生效
