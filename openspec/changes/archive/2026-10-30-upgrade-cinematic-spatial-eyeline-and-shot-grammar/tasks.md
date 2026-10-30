## 1. 数据模型与分镜视线扩展

- [x] 1.1 在 `StudioShot` 与 `DirectorDecisions` 中增加或补齐 `cameraAngle`（机位俯仰：high_angle, low_angle, eye_level）与 `gazeDirection`（视线向量）字段，支持序列化与反序列化
- [x] 1.2 在 `ShotContinuity` 中显式扩充 `elevationLevel`（空间垂直高度：ground, balcony, rooftop 等）以及道具子形态锁定

## 2. 拆镜 System Prompt 与视听语法规则升级

- [x] 2.1 在 `AiConstraintEngine._promptScriptBreakdown5D` 中注入【物理在场过滤硬则】：严禁将内心 OS、回忆、远距离提及的人名填入 `character_ids`
- [x] 2.2 在拆镜 Prompt 中注入【高低位视线轴线与正反打编排规则】：识别二楼与街道空间位差，强制输出俯仰对视参数
- [x] 2.3 在拆镜 Prompt 中注入【法宝与高光特效三联分镜展开（Trinity Shot）】：自动拆解为起手前摇、核心极特写（Insert Shot）与异象全景反馈
- [x] 2.4 在拆镜 Prompt 中注入【道具微动作因果锁】：禁止单镜突变，将撕鸡腿、拔剑出鞘等形变点拆解为具备物理因果的连续微动作

## 3. 生图 Prompt 编译层与第四面墙防御

- [x] 3.1 在 `PromptAssembler.buildShotPrompt` 中实现内心独白脱敏净化器：TTS 保留原著对白，生图 Prompt 自动剔除人名实体，转换为专注闭口与微表情的心理描写
- [x] 3.2 在生图 Prompt 组装中全局强制注入【第四面墙防御】：负向词注入 `looking at camera, eye contact with viewer` 等排他词
- [x] 3.3 实现 `Gaze & Eye-line Compiler`：根据机位俯仰与空间关系编译倾斜视线正向词（如 `looking down at street below at -35 degree angle, 3/4 profile`）

## 4. 导演可执行性校验引擎（C05 与幽灵角色审计）

- [x] 4.1 在 `DirectorValidationEngine` 中增强 C05 规则：核查高海拔机位（二楼）水平平移与地面街景的物理冲突，提示倾斜下摇（Tilt Down）或剪辑切镜
- [x] 4.2 在校验引擎中增加【内心戏幽灵角色检查】：检测内心独白分镜中是否误引入了第三方出场角色，若有则标出阻断或警告

## 5. 验证与工程构建部署

- [x] 5.1 编写单元测试验证物理在场过滤、视线编译器、内心戏台词脱敏与垂直运镜空间校验逻辑
- [x] 5.2 执行 `./scripts/deploy_local.sh` 编译 Release、注入保护并部署本地应用
