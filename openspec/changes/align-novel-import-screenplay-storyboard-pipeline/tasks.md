## 1. AI 约束引擎与单章改编 Schema 升级

- [x] 1.1 升级 `AiConstraintEngine._promptNovelDramaChapterAdaptation`，使其在 output JSON 中明确生成标准 `screenplay_text` 及包含 `dialogue_speaker`、`dialogue`、`subtext`、`action`、`estimated_sec` 的规范 `beats`
- [x] 1.2 升级 `_SchemaValidators.novelChapterAdaptation`，校验 `scenes` 及其 `beats` 的对白与微动作字段，并支持 `screenplay_text` 解析
- [x] 1.3 编写/更新 `AiConstraintEngine` 单章影视化提炼单元测试，验证分场剧本与节拍台词输出规范

## 2. 剧集工程管理与导入流水线持久化重构

- [x] 2.1 修改 `StudioProjectManager.importChapterToEpisode`，增加 `screenplayText` 参数并持久化写入 `StudioEpisode`
- [x] 2.2 在 `importChapterToEpisode` 中将目标集的 `shots` 重置为空列表（`shots: const []`），杜绝陈旧分镜残留
- [x] 2.3 在 `NovelImportTaskService._run` 中，组装完整的文学分场 Markdown 剧本文本并传入 `importChapterToEpisode` 存入工程

## 3. 全局会话激活与交互链路自动导航

- [x] 3.1 修改 `IdeaIncubatorPanel` 导入任务终态监听逻辑：单集导入成功后，通过 `widget.session.selectEpisode` 自动将目标集激活至全局状态
- [x] 3.2 导入成功后触发外壳导航跳转至「剧本工作台」（`StudioStage.screenplay`），并给出友好提示引导创作者先审阅与打磨剧本
- [x] 3.3 检查 `ScreenplayPanel` 的会话监听与生命周期，确保当全局 `session.episode` 刷新时立即呈现提取出的分场剧本与节拍列表

## 4. 分镜看板空状态与剧本承接强化

- [x] 4.1 在 `StoryboardBoard` 中增强空分镜状态检测：当当前集已有场次节拍但无分镜时，展示「剧本已就绪」的转化指引卡片
- [x] 4.2 提供「跳转剧本工作台」与「直接根据剧本生成 5D 分镜」快捷动作，确保分镜镜头严格源自剧本节拍

## 5. 验证与工程门禁

- [x] 5.1 运行全量短视频工坊与约束引擎单元测试，确保无报错、断言全部通过
- [x] 5.2 运行 `openspec validate` 验证本次变更的规划完整性
