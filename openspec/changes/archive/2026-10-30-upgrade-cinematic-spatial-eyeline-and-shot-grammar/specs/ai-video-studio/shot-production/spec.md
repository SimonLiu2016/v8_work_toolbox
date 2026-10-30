## ADDED Requirements

### Requirement: 物理在场角色守卫与内心独白净化

系统在 AI 拆镜与生图提示词组装时 SHALL 严格区分物理在场实体与语言指代客体：
1. 分镜的出场角色列表（`character_ids`）SHALL 仅收录其物理肉身在当前镜头视锥体（Frustum）可视范围内的角色；
2. 角色在内心独白（Inner Voice / OS）、回忆闪回、传音或对话中提及的第三人，系统 SHALL NOT 将其列入该分镜的 `character_ids`；
3. 在组装生图提示词时，对于内心独白（OS）类型的台词，系统 SHALL 自动剥离台词中的人名实体与第三人指代词，转换为闭口、沉思、眼神深邃等微表情提示词，且 SHALL 注入闭口负向词（`mouth open, speaking, talking`），防止生图模型在画面中臆造第三人或让人物张嘴。

#### Scenario: 内心独白提及第三人不生成幽灵角色
- **WHEN** 分镜台词为“姜七夜（内心 OS）：今天真晦气，又被老王训了一顿”
- **THEN** 拆镜算法生成的该分镜 `character_ids` SHALL 仅包含姜七夜，不包含老王
- **AND** 生图 Prompt SHALL 描述姜七夜骑驴漫步、神态沉思闭口，且不出现老王名字与老王外貌特征

#### Scenario: 内心独白强制闭口
- **WHEN** 分镜的台词发声类型为 `inner_voice` 或包含“内心 OS”
- **THEN** 系统组装的生图 Prompt SHALL 注入自然闭口与心理微表情指令
- **AND** 负向提示词 SHALL 包含 `mouth open, speaking, parted lips, talking`

### Requirement: 视线轴线与第四面墙防御

系统在生成人物分镜画面时 SHALL 遵循电影视听视线轴线（Eye-line Match），禁止角色无故直视镜头（Breaking the Fourth Wall）：
1. 除明确的旁白者解说或打破第四面墙的特殊戏剧指令外，系统组装生图 Prompt 时 SHALL 默认注入防直视镜头负向词（`looking at camera, eye contact with viewer, facing viewer directly`）；
2. 当场景中存在明确的对话或对峙对象时，系统 SHALL 依据两者的空间相对方位（方位角与俯仰位差）为人物指定视线方向（`gaze_direction`）；
3. 人物在画面中的视线与脸部朝向 SHALL 呈现侧向、半侧向（3/4 profile）或朝向倾听者方位，严禁面对观众自言自语。

#### Scenario: 高低位对峙视线对齐
- **WHEN** 二楼栏杆处的余小白向街面上的姜七夜喊话
- **THEN** 余小白分镜的视线指令 SHALL 为朝向画面下方街面俯视（`looking down at street below`），机位为高角度俯拍（`high angle shot`）
- **AND** 姜七夜分镜的视线指令 SHALL 为朝向斜上方二楼仰望（`looking up towards 2nd floor balcony`），机位为低角度仰拍（`low angle shot`）
- **AND** 两个分镜均注入防直视镜头排他词，双方均不直视观众屏幕

#### Scenario: 双人对话正反打镜头排布
- **WHEN** 两个角色发生连续多句对白
- **THEN** 拆镜引擎 SHALL 组织正反打（Shot-Reverse-Shot）机位交替，双方视线在左右屏幕轴线上互斥对称，呈现真实的视线交流

### Requirement: 关键法宝与特效三联分镜展开

当原著剧情涉及法宝激活、神兵出鞘、法术轰击或高光动作特效时，系统 SHALL NOT 将其压缩在单一普通全景或对白分镜中，而 SHALL 采用专业影视“三联分镜语法（Trinity Shot Grammar）”进行视听拆解：
1. **起手前摇镜头（Setup Shot）**：展示角色手势掐诀、蓄势起步或神情骤变（中景或中近景）；
2. **核心物件特写镜头（Insert Detail Shot）**：以微距或极特写（Extreme Close-Up / Macro）聚焦法宝、符文亮起、刀刃流光或机关转动；
3. **异象冲击与环境反应镜头（Payoff & Reaction Shot）**：以全景或广角展现气流爆发、光华冲霄、建筑震动或路人惊骇反应。

#### Scenario: 识别法宝台词自动派生极特写插镜
- **WHEN** 原著剧情在对白中驱动法宝生效（如握持神秘法珠念咒）
- **THEN** 拆镜引擎生成的镜头序列中 SHALL 包含至少一个专属于法宝核心材质、光效与符文细节的极特写分镜（Insert Shot）
- **AND** 该特写分镜的提示词 SHALL 聚焦法宝微观质感与能量演变，不被全身构图稀释
