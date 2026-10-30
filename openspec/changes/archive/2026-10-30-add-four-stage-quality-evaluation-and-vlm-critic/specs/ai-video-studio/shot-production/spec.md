## ADDED Requirements

### Requirement: 基于多模态大模型（VLM）的关键帧实拍场记自动审图验收 (VLM Keyframe Visual Critic)
系统 SHALL 提供关键帧实拍场记视觉验收服务（`KeyframeVisualCritic`），利用多模态视觉大模型（VLM）对已生成的分镜关键帧图片（`shot_N.png`）与分镜脚本设定进行自动比对核验：
1. **四维视觉核验指标**：
   - **人数与防克隆核验（Character Count & Anti-Clone）**：核验画面实际人物数量是否匹配剧本预期，是否存在面容/服饰重复的克隆双胞胎伪影。
   - **空间高差与透视核验（Spatial Elevation & Perspective）**：核验高低落差场景（如楼上与街面）是否符合透视规律，拦截“高空悬空平地并立”等透视崩坏。
   - **坐骑与核心道具核验（Mount & Prop Continuity）**：核验分镜要求的坐骑（如骑乘黑驴）或核心手持道具是否在画面中真实存在且姿态正确（骑姿而非直立站地）。
   - **景别与构图核验（Shot Scale & Framing）**：核验实际成图景别是否符合分镜规定的远景/中景/近景/特写要求。
2. **结构化审图结果持久化**：审图结果（总分 0-100、是否通过 `passed`、各项核验状态、问题摘要 `issues`、提示词修正建议 `promptFixSuggestion`）MUST 持久化至 `StudioShot.vlmCriticReport`。
3. **UI 状态呈现与闭环重抽**：在分镜卡片与「连环画预审（Previs）」卷轴中，系统 MUST 展示 VLM 审图徽章（通过/未通过及分数）；当审图未通过时，提供「采纳建议并重抽关键帧」快捷操作，将 VLM 给出的构图修正建议自动注入分镜补充约束并触发重新生图。

#### Scenario: VLM 检出关键帧中人物悬空并立与坐骑丢失
- **WHEN** 分镜 #2 要求“余小白在三楼窗口俯视，姜七夜在街面骑黑驴”，但生成的 `shot_2.png` 中两人平地并排站立且无黑驴，用户执行「VLM 审图验收」
- **THEN** `KeyframeVisualCritic` SHALL 将该镜头的 `vlmCriticReport.passed` 置为 `false`，指出“空间高差缺失（平地并立）”与“坐骑大黑驴缺失”，并在分镜卡与连环画卷轴上展示红色告警徽章与一键修正重抽入口
