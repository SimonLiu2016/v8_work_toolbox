## Purpose

为短视频工坊全流程 AI 交互（策划、剧本、分镜、提示词装配、门禁质检等）提供集中化注册、动态变量插槽解析、用户自定义覆盖、出厂自愈与模板导入导出管理能力。

## ADDED Requirements

### Requirement: 全流程 AI 提示词集中注册与出厂预设

系统 SHALL 提供统一的提示词模板注册中心（`StudioPromptTemplate` 与 `StudioPresetStore`），涵盖短剧全生产流程的所有关键 AI 任务，包括但不限于：
1. 编剧研讨室主线与边界抽取（`writers_room_master_extract`）
2. 全季分集节拍大纲规划（`writers_room_season_beats`）
3. 编剧研讨共创对话（`writers_room_dialogue`）
4. 小说转分场剧本生成（`screenplay_novel_adapt`）
5. 环境生态常识推演规则（`screenplay_plausibility_rules`）
6. 竖屏短剧高能节拍法则（`screenplay_beat_pacing_rules`）
7. 竖屏 9:16 五维拆镜规范（`storyboard_vertical_5d`）
8. 视觉生图与视频提示词装配（`visual_prompt_assembly`）
9. 全局工业级负向规避词库（`negative_prompt_library`）
10. 导演门禁质检审查与自愈重写（`director_audit_critic` 与 `director_audit_autofix`）

所有模板必须具备完备的出厂默认值（`defaultContent`），当本地配置文件损坏或缺失时 SHALL 自动补齐自愈，不得中断业务执行。

#### Scenario: 首次启动或配置缺失时自动填充出厂预设
- **WHEN** 应用启动或提示词模板文件缺失/为空
- **THEN** 系统自动载入全部内置出厂预设模板并持久化至本地存储，所有下游 AI 任务均能正确读取默认规则

### Requirement: 动态变量插槽解析与优先级覆盖

系统在调用任一 AI 任务生成时，SHALL 优先读取用户在设置中自定义的提示词覆盖（`userOverride`），仅在未设置自定义内容时回退至出厂默认内容。系统 SHALL 支持声明式动态变量插槽（如 `{{series_name}}`、`{{worldview}}`、`{{character_names}}`、`{{pacing_rules}}` 等），在发起大模型请求前自动将上下文数据注入对应插槽。

#### Scenario: 用户自定义提示词生效并完成变量替换
- **WHEN** 用户在设置中修改了 `screenplay_beat_pacing_rules` 模板并保存，随后在剧本工作台触发小说转剧本
- **THEN** 系统读取用户自定义的节拍规则内容，自动将当前剧集的角色与场景列表注入变量插槽，生成发给大模型的最终系统提示词

### Requirement: 提示词管理界面与导入导出

系统 SHALL 在工坊设置中心提供可视化的提示词管理界面，支持按类别（策划、剧本、分镜、质检等）浏览各模板、查看出厂默认与当前覆盖内容、在线编辑并实时保存。系统 SHALL 提供单项与全部模板的「一键恢复出厂预设」操作，并支持将当前配置导出为 JSON 模板文件或从 JSON 文件导入外部预设包。

#### Scenario: 单项一键恢复出厂预设
- **WHEN** 用户点击某提示词模板旁的“恢复出厂默认”按钮并确认
- **THEN** 系统清除该模板的 `userOverride` 标记，界面与下游执行均实时切换回官方出厂预设

#### Scenario: 导出与导入提示词预设包
- **WHEN** 用户在管理界面点击“导出预设包”
- **THEN** 系统将当前全量提示词模板（含用户自定义内容）导出为带有缩进的 JSON 文件供其他设备导入复用
