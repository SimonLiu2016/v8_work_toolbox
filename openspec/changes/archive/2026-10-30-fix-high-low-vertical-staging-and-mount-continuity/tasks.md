## 1. 垂直高低位空间调度与透视提示词修复

- [x] 1.1 在 `PromptAssembler` 中升级高低位同框空间关系编译，当镜头包含楼层高差（如三楼/二楼 vs 街面）时，自动转译为单向过肩构图（OTS）或明确物理高差，严禁输出平地并排提示词
- [x] 1.2 修复景别与主体矛盾：当景别为远景/全景时，禁止高位角色输出“处于画面主体近景”，统一转为前景构图框（Framing Element）描述
- [x] 1.3 修复同框角色主体分工冲突：在 `PromptAssembler.buildCharacterStagingPrompt` 中强制约束单一 `subject`（主体），同框其余角色自动收敛为 `confrontation` 或 `supporting`

## 2. 坐骑与载具跨镜头状态台账继承

- [x] 2.1 在 `ShotContinuity` 与节拍状态解析中增加坐骑伴随状态跟踪（`mountOrVehicle`）
- [x] 2.2 在 `AiConstraintEngine.convertScenesToShots` 与连续性台账流转中，若上一镜为骑乘状态且未发生下骑事件，自动继承骑乘姿势与坐骑实体提示词，杜绝直立站姿

## 3. Keyframe 首尾帧模式参考标签净化（Anti-Ghosting）

- [x] 3.1 在 `PromptAssembler.buildVideoGenPrompt` 中注入模式感知逻辑，当 `mode == 'keyframe'` 且首帧图片已存在时，自动剔除 `【素材指代】` 模块
- [x] 3.2 将提示词与因果时间轴中的 `<Picture N>` 标签在 `keyframe` 模式下自动替换为纯角色名，消除视频扩散模型的多重主体克隆

## 4. 自动化测试与工程验证

- [x] 4.1 编写单元测试覆盖高低位空间过肩编译、坐骑连续性继承以及 keyframe 模式标签净化
- [x] 4.2 运行 `flutter analyze` 确保零错误、零警告
- [x] 4.3 运行 `openspec validate fix-high-low-vertical-staging-and-mount-continuity --strict` 确保规范校验通过
