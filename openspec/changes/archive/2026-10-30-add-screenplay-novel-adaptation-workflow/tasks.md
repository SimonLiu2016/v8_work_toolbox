## 1. 小说正文影视化改编弹窗开发

- [x] 1.1 创建 `ScreenplayNovelAdaptDialog`（`lib/tools/ai_video_studio/ui/screenplay_novel_adapt_dialog.dart`）基础双通道页签框架（从小说库选章节 vs 直接粘贴正文）
- [x] 1.2 实现通道 A（小说库章节选择）：自动加载当前剧集关联的 `novelId` 章节目录，展示章节序号、标题、字数，支持快捷多选连续章节，实时计算总字数并在 3,000~8,000 字时显示最佳精读区间推荐
- [x] 1.3 实现通道 B（自由正文粘贴）：支持多行文本框粘入外部小说正文，支持实时字数统计与超出 12,000 字时的拆分建议警告
- [x] 1.4 实现未关联小说时的友好引导：若当前剧集尚未绑定 `novelId`，允许用户直接从本地小说库中挑选一部小说建立关联

## 2. 剧本工作台就地改编逻辑与数据沉淀

- [x] 2.1 在 `ScreenplayPanel`（`lib/tools/ai_video_studio/ui/screenplay_panel.dart`）实现 `_adaptFromNovelText`，调用 `AiConstraintEngine.adaptNovelDramaChapter` 通读输入文本
- [x] 2.2 调用 `StudioProjectManager.importChapterToEpisode` 将提炼的戏剧场次、文学剧本正文与受保护台词/事实契约（`ProtectedContract`）沉淀至当前集，并自动增量合并角色卡与场景空间档案
- [x] 2.3 刷新内存态剧本与编辑器文本控制器，展示完成提示条并播报锁定的原著金句与事实条数

## 3. 剧本工作台 UI 入口重构与智能引导

- [x] 3.1 改造 `ScreenplayPanel._buildScenesList` 中央空白引导区：新增「从小说正文改编剧本（推荐）」主按钮，将原有基于大纲的生成调整为清晰的次级入口
- [x] 3.2 改造顶部工具栏：将主操作定义为「从小说正文生成剧本」，将原有的 100 字大纲扩写调整为次级操作（如下拉项或次级按钮「根据大纲扩写」）
- [x] 3.3 增加防误触安全拦截：当 `_scenes.isNotEmpty` 时，触发任一重新生成操作前先弹出覆盖确认对话框
- [x] 3.4 在 Markdown 文本模式下增加散文智能探测横幅：当文本长度超过 500 字且不包含分场标记时，浮现一键 AI 改编为分场剧本的操作横幅

## 4. 验证与本地部署

- [x] 4.1 编写单元测试覆盖正文改编数据沉淀、受保护契约绑定与防误触拦截逻辑（`test/tools/ai_video_studio/`）
- [x] 4.2 运行 `flutter analyze` 确保零错误、零警告
- [x] 4.3 运行 `openspec validate add-screenplay-novel-adaptation-workflow --strict` 确保规格严格合规
- [x] 4.4 执行 `./scripts/deploy_local.sh` 重新构建并替换本机 `/Applications/V8WorkToolbox.app`
