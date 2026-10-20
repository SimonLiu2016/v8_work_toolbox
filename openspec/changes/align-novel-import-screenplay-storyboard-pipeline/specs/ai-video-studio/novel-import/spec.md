## ADDED Requirements

### Requirement: 单章小说导入产出文学分场剧本与节拍台词

系统 SHALL 在小说单章导入或单集增量扩写时，同步提炼生成包含【分场文学剧本（Markdown `screenplayText`）】及结构化【戏剧场次（`scenes`）与微动作节拍（`beats`）】。每个节拍 SHALL 明确包含角色台词（`dialogue`）、说话人（`dialogueSpeaker`）、潜台词（`subtext`）与聚焦微动作（`action`）。系统 SHALL 在持久化写入目标集时完整落盘 `screenplayText`，同时 SHALL 重置清空该目标集内可能残留的旧分镜（`shots: []`），杜绝旧分镜污染新导入内容。

#### Scenario: 单章小说导入同步生成分场剧本并重置陈旧分镜
- **WHEN** 用户选择导入小说某一章节并指定写入目标集数
- **THEN** 系统解析后生成包含 Markdown 格式文本的文学剧本（`screenplayText`）及带有对白与微动作的戏剧场次列表（`scenes`），并将目标集原有的分镜列表重置为空，确保不会混杂旧分镜

### Requirement: 导入完成后的剧集上下文激活与工作流引导

系统 SHALL 在小说单章导入任务完成后，自动将目标集设置为全局激活集（`session.selectEpisode`），并将界面路由或视觉焦点引导至「剧本工作台」，使用户能立即对刚刚生成的剧本分场、对白与节拍进行审阅与动作超载检查。

#### Scenario: 导入完成后自动激活当前集并引导至剧本工作台
- **WHEN** 小说单章解构流水线执行完毕并成功落盘
- **THEN** 系统自动将目标集注入全局 session，外壳自动导航至「剧本工作台」，剧本工作台完整渲染当前集提炼出的分场剧本与节拍列表
