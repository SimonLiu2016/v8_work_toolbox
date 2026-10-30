## 1. 数据模型与底层解析增强

- [x] 1.1 在 `StudioEpisode` 模型中新增 `novelChapterRange` 与 `novelChapterIndices` 字段并实现 JSON 序列化与向后兼容反序列化
- [x] 1.2 在 `AiConstraintEngine` 中实现章节范围字符串智能解析算法 `_parseChapterRange`（支持 "1-3"、"第1~3章"、"1, 2, 3" 等格式及平滑插值兜底）
- [x] 1.3 升级 `AiConstraintEngine` 的宏观大幕与分集规划 Prompt、JSON Schema 及其校验器，约束大模型输出各集取材章节信息

## 2. 编剧研讨室界面与落库持久化

- [x] 2.1 在 `WritersRoomDialog` 的分集卡片上展示原著章节徽章 `[原著第 X~Y 章]`
- [x] 2.2 实现方案 A：点击章节徽章唤起章节范围微调弹窗，支持创作者手动输入并即时更新分集章节映射
- [x] 2.3 在 `_writeEpisodesToSeries` 中将每集的 `chapter_range` 与 `chapter_indices` 持久化写入 `StudioEpisode`

## 3. 剧本工作台与小说改编弹窗联动

- [x] 3.1 改造 `ScreenplayPanel`：在未生成剧本时依据 `novelChapterRange` 动态展示“精读原著第 X~Y 章改编”入口文案与提示
- [x] 3.2 改造 `ScreenplayNovelAdaptDialog`：接收分集目标章节列表 `targetChapterIndices`，自动预选多选所有对应章节，并展示研讨室推荐提示
- [x] 3.3 确保确认改编时全量读取并拼接所选全部章节的正文全文送入 AI 深度影视化提炼

## 4. 自动化测试与本地应用部署

- [x] 4.1 编写单元测试验证 `StudioEpisode` 章节字段序列化、章节范围解析容错、研讨室分集章节持久化与工作台章节联动逻辑
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，端到端验证研讨室规划映射与工作台多章预选精读改编流程
