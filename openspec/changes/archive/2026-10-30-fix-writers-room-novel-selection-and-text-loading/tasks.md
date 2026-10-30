## 1. 模型与正文加载自愈能力 (Model & Text Loading)

- [x] 1.1 在 `NovelSelectionResult` 中实现 `loadCombinedText()` 异步方法，支持根据小说 ID 与勾选章节批量读取拼接正文

## 2. 编剧研讨室正文读取与分析联动 (Writers Room Workflow)

- [x] 2.1 在 `WritersRoomDialog._pickFromNovelLibrary` 中接入 `loadCombinedText()`，并呈现“正在载入正文”的中间加载状态
- [x] 2.2 在 `WritersRoomDialog` 中增加章节内容为空时的防御判断与 SnackBar 友好提示
- [x] 2.3 确保正文就绪后自动启动 `_runMacroAnalysis()` 并推进至全季分集大纲策划工作台

## 3. 大模型上下文采样保护 (Context Window Protection)

- [x] 3.1 在 `AiConstraintEngine.extractWritersRoomMaster` 中接入 `sampleNovelTextForContext`，限制 Prompt 上下文字符预算在 35,000 字以内

## 4. 自动化测试 (Automated Tests)

- [x] 4.1 编写 `test/writers_room_novel_selection_test.dart` 自动化测试，覆盖 `loadCombinedText` 章节批量读取、全本自愈提取、空内容拦截以及长文智能采样防护

## 5. 本地部署与验收 (Deployment)

- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，端到端实机验证编剧研讨室小说导入流程
