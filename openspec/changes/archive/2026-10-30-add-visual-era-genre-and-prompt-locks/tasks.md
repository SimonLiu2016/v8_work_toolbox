## 1. 数据模型与时代题材知识库 (`VisualEraGenre`)

- [x] 1.1 在 `lib/tools/ai_video_studio/models/studio_models.dart` 中建立 `VisualEraGenre` 领域模型，定义中英标签、正向服饰锚点、环境/材质锚点与排他负向词典（内置仙侠修真、古装武侠/穿越、现代都市豪门、科幻异能、末日废土、未来科幻/赛博、异世界奇幻等预设）。
- [x] 1.2 在 `StudioSeries` 模型中增加 `eraGenre` 字段，更新 `copyWith`、`toJson`、`fromJson` 保持对既有存档的平滑兼容。

## 2. 提示词组装引擎升级与 IP 主库生图链路闭环

- [x] 2.1 `lib/tools/ai_video_studio/services/prompt_assembler.dart`：升级 `CharacterTurnaroundPrompt.build`，支持传入 `styleTokens` 与 `VisualEraGenre? eraGenre`，按「视角结构 -> 时代服饰锚点 -> 角色本征 -> 风格锁」拼装正向，复合「三视图缺陷 + 时代穿帮排他（如现代短裤/T恤/球鞋等）」拼装负向。
- [x] 2.2 `lib/tools/ai_video_studio/ui/series_page.dart`：角色三视图生成 `_generateTurnaround()` 传入所属剧集的 `styleTokens` 与 `VisualEraGenre.fromId(widget.series.eraGenre)`，杜绝下半身与时代穿帮。
- [x] 2.3 `lib/tools/ai_video_studio/ui/series_page.dart`：道具生成 `_generateImage()` 与场景生成 `_generateImage()` 全面注入全局 `styleTokens`、对应题材的材质/环境锚点与时代排他负向词。
- [x] 2.4 `lib/tools/ai_video_studio/ui/series_page.dart`：角色卡「生成 Prompt」移除硬编码的 `'drama'`，动态传入所属剧集的真实 `productionType`、`worldview` 及 `eraGenre`。

## 3. AI 约束引擎与小说导入提炼升级

- [x] 3.1 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：升级 `promptTranslation` 方法与系统提示词，支持接收世界观与时代题材上下文，在翻译时指导大模型补全时代服饰形制。
- [x] 3.2 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：升级 `_promptNovelMasterExtraction`，在输出 Schema 中增加 `era_genre`，并在角色提取中强调时代服饰规范。
- [x] 3.3 `lib/tools/ai_video_studio/services/novel_import_task_service.dart`：在小说全案提炼完成写入时，解析并保存 `series.eraGenre`，使导入剧集开箱自带匹配的时代锁。

## 4. UI 界面交互与设定联动

- [x] 4.1 `lib/tools/ai_video_studio/ui/series_page.dart`：在世界观 Tab 顶部增加「时代与题材设定」芯片选择器，直观展示中文标签，支持快速切换题材并实时展示生效的服饰锚点与排他词预览。

## 5. 质量验证与部署

- [x] 5.1 编写/补充单元测试，验证 `VisualEraGenre` 预设检索、三视图提示词时代排他注入、小说提炼与道具生图的正确性。
- [x] 5.2 运行 `flutter analyze lib/tools/ai_video_studio` 与 `flutter test test/tools/ai_video_studio/` 确保零错误零告警。
- [x] 5.3 按照工程规范执行 `./scripts/deploy_local.sh` 编译并热替换本机应用。
