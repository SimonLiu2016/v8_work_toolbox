## 1. 剧本模型与内心独白 (OS) 基础设施

- [x] 1.1 在 `lib/tools/ai_video_studio/models/drama_director_contract.dart` 中为 `DramaBeat` 增加 `voiceType`（类型为 `UtteranceVoiceType`，支持 `dialogue`、`innerVoice`、`narration`，默认 `dialogue`），并更新其 `copyWith`、`toJson` 与 `fromJson`。
- [x] 1.2 在 `lib/tools/ai_video_studio/ui/screenplay_panel.dart` 中升级文学剧本 Markdown 导出器（`_exportToMarkdown`），当发声类型为 `innerVoice` 时清晰排版为 `角色名（内心 OS）：内容`，呈现标准电影文学剧本视觉。
- [x] 1.3 在 `test/tools/ai_video_studio/` 相应单元测试中补充对 `DramaBeat.voiceType` 序列化与 Markdown 导出的测试断言。

## 2. 影视文学改编提示词重构（去刻板短剧偏见）

- [x] 2.1 重写 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` 中的 `_promptNovelDramaChapterAdaptation`：彻底清洗“爆款短剧”、“前3秒核心危机受辱”等低俗诱导，确立原著人物性格与爽点自适应法则，在节拍中原生支持 `voice_type: "inner_voice"`。
- [x] 2.2 重构 `ai_constraint_engine.dart` 中的 `_promptScreenplayGeneration`：剔除具有误导性的暗黑压抑客栈示例，确立标准分场文学剧本文风，使输出兼具高戏剧连贯性与角色心理动机。
- [x] 2.3 优化 `ai_constraint_engine.dart` 中的 `_promptNovelEpisodeSegmentation`：规范标题生成规则，杜绝流水线式《长街受辱》命名，回归小说原汁原味的文学与事件标题。

## 3. 原生纯中文导演语言编译器重构 (`PromptAssembler`)

- [x] 3.1 重构 `lib/tools/ai_video_studio/services/prompt_assembler.dart` 中的 `compileShot` 与 `compileSegment`：彻底废弃英文伪渲染器咒语堆叠（移除 `UE5 render`, `Octane render`, `3D CGI`），优先提取纯中文体态服装（`descriptionZh`, `facialFeaturesZh`, `defaultAttireZh`）与场景置景（`descriptionZh`），编译为纯中文结构化导演镜头指令。
- [x] 3.2 在 `PromptAssembler` 中落实严格的音画分流机制：当镜头包含内心独白（OS）时，指令画面角色保持自然闭口与微表情，台词标记为画外配音音轨，避免画面汉字乱码与嘴型畸变。
- [x] 3.3 在 `test/ai_video_studio_prompt_assembler_test.dart` 中补充针对纯中文导演语言组装与音画分流的单元测试。

## 4. 自动化验证与本机部署

- [x] 4.1 运行 `flutter analyze` 确保所有修改文件 0 错误 0 警告。
- [x] 4.2 运行工坊剧本与 Prompt 组装相关单元测试，确保全绿无回归。
- [x] 4.3 执行工程核心命令 `./scripts/deploy_local.sh` 重新构建、签名并热替换部署本机应用。
