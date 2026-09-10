## 1. Python 提取器增强（本地数据库与明文还原）

- [x] 1.1 在 `scripts/evernote_import.py` 中实现 `detect_local_evernote`，自动寻找并验证本机印象笔记/Evernote 容器数据库与 content 目录
- [x] 1.2 在 `scripts/evernote_import.py` 中实现 `import_local` 命令，读取 `ZENNOTEBOOK`、`ZENNOTE`、`ZENTAG` 及对应 `content.enml`，完整导出为 JSON 数据流
- [x] 1.3 在 `scripts/evernote_import.py` 的 `parse_notes` 中增加本地数据库明文回退机制：当 XML 笔记内容为 `base64:aes` 时，自动从本地 `content.enml` 中提取明文替代

## 2. Dart 导入服务升级（自动建本与一键全量迁移）

- [x] 2.1 在 `lib/tools/notebook/evernote_import_service.dart` 中实现 `detectLocalEvernote()`，返回本地账号、笔记本数与笔记数
- [x] 2.2 在 `lib/tools/notebook/evernote_import_service.dart` 中实现 `importFromLocalClient()`，调用 `import_local` 执行全量免密秒级导入
- [x] 2.3 在 `importFromNotesFile` 中修复笔记本丢失问题：提取文件主名（如 `我的笔记`）作为默认笔记本名，并在数据库中自动创建和归属笔记

## 3. UI 交互与体验升级

- [x] 3.1 在 `lib/tools/notebook/ui/notebook_page.dart` 的导入弹窗中展示检测到的本机印象笔记信息，并提供“一键全量迁移”主推荐操作
- [x] 3.2 保留“选择 .notes / .enex 文件导入”备选操作，并在导入后自动选中刚导入的笔记本

## 4. 验证与发布

- [x] 4.1 运行测试套件与静态语法检查 `flutter analyze --no-fatal-infos`
- [x] 4.2 运行导入测试，验证真实笔记本结构、明文正文与附件迁移成功
- [x] 4.3 构建 macOS Release 版本并重启验证
