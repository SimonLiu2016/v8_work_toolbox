## 1. 扩充适配器与台账快照数据结构

- [x] 1.1 在 `video_gen_adapter.dart` 中实现脱敏 payload 生成（将 base64 替换为长度摘要），并在 `requestSnapshot` 中独立记录 `firstFramePath`、`lastFramePath`、`referencePaths`、`rawPayload`，并实现键名双写对齐。
- [x] 1.2 在 `video_task_ledger.dart` 中确保 `requestSnapshot` 完整保留并支持检索新增字段。

## 2. 改造试炼场草稿模型与解析器

- [x] 2.1 在 `PlaygroundDraft` 中新增 `rawPayload` 字段及 `formattedRawPayloadJson` 格式化导出方法。
- [x] 2.2 重构 `PlaygroundDraft.fromLedgerEntry`：支持 `aspectRatio`/`ratio`、`sizeTier`/`resolution`、`durationSec`/`durationSeconds` 双字段回退读取；独立恢复首帧、尾帧与参考图角色，消除模式互斥拦截；提供老版本数据容错。

## 3. 增强试炼场与看板的真实请求查看与复制能力

- [x] 3.1 改造 `PlaygroundPage` 中的 `_showRequestView`：支持一键「复制完整请求 JSON」与「复制参数文本」到系统剪贴板，并支持切换/查看脱敏 HTTP JSON。
- [x] 3.2 在 `storyboard_board.dart` 的 `_CloudTaskTile` 中新增「查看请求体」弹窗与一键复制功能，支持未进入试炼场时直接核对与导出底层网络请求。

## 4. 自动化测试与工程验证

- [x] 4.1 编写单元测试验证 `PlaygroundDraft.fromLedgerEntry` 对画幅比例、素材角色及 `rawPayload` 的保真解析与老版本兼容。
- [x] 4.2 运行 `flutter analyze` 与相关测试确保无语法与回归问题。
- [x] 4.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用。
