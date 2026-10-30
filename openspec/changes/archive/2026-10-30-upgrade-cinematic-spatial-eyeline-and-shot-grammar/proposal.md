## Why

当前 AI 漫剧分镜生成与视频成片存在六大严重的影视视听语法断裂与生成幻觉：
1. **内心独白引发幽灵角色**：分镜内心 OS 提到第三人（如“姜七夜内心 OS：又被老王训了一顿”），AI 拆镜将其误判为出场角色，下游生图强行渲染老王牵驴（#4, #5）；
2. **打破第四面墙与视线轴线丢失**：所有人物均直视镜头屏幕（Looking at viewer），高低位对话（如二楼余小白与地面姜七夜）缺乏高低俯仰对视与视线匹配（Eye-line Match），两人双双对着观众自言自语（#5, #7, #9, #10）；
3. **空间几何与运镜轨迹崩塌**：二楼机位平视平移（Pan Right）竟然直接瞬移出地面长街与马车，违背三维空间物理视野约束（#8）；
4. **对话镜头缺乏影视正反打**：双人隔空/空间对峙没有过肩镜头（OTS）与视线交替，导致站位朝向混乱；
5. **道具物体拓扑崩溃**：单镜头复合动作缺乏因果相位约束，导致“整只烤鸡”在送到嘴边时突变为“鸡腿”（#11）；
6. **高光特效缺乏影视拆解**：一句关键施法或法宝台词只分配一个普通镜头，缺乏特写插镜（Insert Shot）与视听反应，画面平淡无奇（#13）。

必须将分镜拆解与提示词编译体系从简单的“文本断句”全面升级为具备**空间拓扑几何、物理在场隔离与经典电影语法**的专业影视导演体系。

## What Changes

1. **角色物理在场过滤与内心独白净化（Physical In-Scene Guard & Monologue Sanitizer）**：
   - 拆镜算法中强制执行物理在场判据：`character_ids` 严禁收录心声/OS/回忆/远距离提及的人名；
   - 生图 Prompt 编译层对内心独白执行自动脱敏：配音保留原著台词，但生图描述中剔除无关第三人实体名词，专注神态微表情与闭口沉思，杜绝幽灵角色。
2. **空间视线轴线与高低位正反打导演语法（Spatial Eye-line & Shot-Reverse-Shot）**：
   - 分镜数据模型扩充视线向量（`gaze_direction`）与机位俯仰角（`camera_angle`: high/low/eye_level）；
   - 双人高低位空间对峙（如二楼 vs 街道）自动生成高低俯仰对视参数，全局强制注入“防直视镜头/防打破第四面墙”负向词；
   - 自动排布过肩镜头（OTS）与视线互斥对齐，根绝人物背对倾听者面对观众说话的违和感。
3. **空间物理边界与运镜合法性守卫（Spatial Camera Movement Guard）**：
   - 升级 C05 连续性校验引擎：在二楼高位机位下，水平平移（Pan）禁止瞬移出地面视野；跨空间高度转场强制要求下摇（Tilt Down）或剪辑硬切（Cut）。
4. **道具拓扑状态机与微动作因果锁（Prop Topology & Micro-beat Causality）**：
   - 针对道具变化（如整鸡 ➔ 鸡腿），强制拆解为微动作连续分镜（手持整鸡 ➔ 撕下鸡腿 ➔ 咬下鸡腿），通过连续性台账锁定道具状态，杜绝单镜突变。
5. **法宝/高光动作“三联镜头语法”（Trinity Shot Grammar for VFX & Artifacts）**：
   - 拆镜引擎识别法宝施法与核心特效时，强制派生三联镜头：起手前摇（Setup）➔ 核心物件极特写（Insert Detail Macro）➔ 异象冲击/全景反应（Payoff Reaction）。

## Capabilities

### Modified Capabilities
- `ai-video-studio/shot-production`: 增加物理在场角色守卫、内心独白脱敏、视线轴线（Eye-line）与第四面墙防御，支持法宝特效三联特写分镜。
- `ai-video-studio/shot-continuity`: 增加空间垂直高低位机位俯仰、高低视线对齐、跨高度运镜物理校验与道具微动作拓扑状态锁。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/models/studio_models.dart`: 扩充分镜视线与机位俯仰字段；
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 升级拆镜 Prompt，注入物理在场、三联特写与高低正反打调度；
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 实现内心独白脱敏净化器与视线编译器，注入第四面墙防御；
  - `lib/tools/ai_video_studio/services/director_validation_engine.dart`: 升级 C05 空间连续性规则，增加垂直高度机位运动与幽灵角色拦截。
- **Affected Tests**:
  - 增加导演语法、视线对齐、内心戏幽灵过滤与三联特写分镜的单元测试。
