## 1. 提示词中枢注册与插槽解析引擎 (Configurable Prompt Registry)

- [x] 1.1 在 `StudioPromptTemplate` 与 `StudioPresetStore` 中补全所有出厂模板定义（涵盖策划、常识推演规则、短剧节拍法则、竖屏9:16拆镜、正负向词库与质检自愈）
- [x] 1.2 在 `AiConstraintEngine` 中实现统一的 `resolveSystemPrompt` 机制，支持用户自定义覆盖优先级与 Mustache 双花括号 `{{variables}}` 动态插槽解析
- [x] 1.3 升级工坊设置中心（`StudioSettingsDialog`），提供可视化提示词规则分类树、富文本编辑、变量插槽提示、一键恢复出厂预设及 JSON 预设包导入导出功能

## 2. 环境生态与社会常识推演引擎 (Environmental Plausibility)

- [x] 2.1 编写并调优 `screenplay_plausibility_rules` 模板：约束公共开放空间（街市/酒肆/广场）异常事件强制生成路人 NPC 围观与生态反应；隐秘事件自动修正至死胡同/暗角/深夜
- [x] 2.2 在 `AiConstraintEngine.adaptNovelDramaChapter` 与 `screenplayGeneration` 中动态装配环境常识推演规则
- [x] 2.3 在 `DirectorValidationEngine` 中新增门禁 C10（环境常识与社会反应闭环审查），自动识别公共场所无反应孤立穿帮

## 3. 竖屏短剧高能节拍与动作化引擎 (Micro-drama Beat & Pacing)

- [x] 3.1 编写并调优 `screenplay_beat_pacing_rules` 模板：落实黄金 3 秒高压切入、15 秒情绪阶梯递进、心理描写动作化转化器、片尾极限断章卡点钩子
- [x] 3.2 优化单集剧本生成与解析逻辑，确保文学剧本与场次节拍中结构化保留微表情、道具交互与悬念状态
- [x] 3.3 在 `DirectorValidationEngine` 中新增门禁 C11（黄金3秒与片尾断章卡点审查），拦截平淡流水账与平缓收尾

## 4. 竖屏 9:16 工业分镜与提示词装配 (Vertical 9:16 Storyboard)

- [x] 4.1 升级 `scriptBreakdown5D` 拆镜规则：约束中近景特写偏好（≥70%）、单镜头肉身在场角色 ≤ 3 人、四人以上群像自动拆解为环境建立镜与连续正反打、底部 1/5 字幕安全区保护
- [x] 4.2 完善 `PromptAssembler`：模块化拼接美学风格前缀、角色视觉锚点、场景七方位光影与具象微动作，并自动注入可配置的负向防崩坏词库

## 5. 编剧研讨室策划共创工作流 (Writers' Room)

- [x] 5.1 实现小说长文宏观分析任务，提取《故事主线脉络表》与必留/可删/可改三类情节清单
- [x] 5.2 在创意策划/剧集界面提供编剧研讨会话面板，支持制片人身份对话调强大纲并动态更新全季 30 集单集冲突与结尾钩子

## 6. 验证、测试与工程部署

- [x] 6.1 编写插槽解析、环境常识规则装配与 C10/C11 门禁的自动化测试用例
- [x] 6.2 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，端到端验证小说转剧本与分镜的合理性与节奏紧凑度
