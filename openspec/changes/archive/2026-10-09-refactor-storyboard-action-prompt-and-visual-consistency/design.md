## Context

在目前的 AI 视频工坊中，`PromptAssembler` 虽有 `parts.actionZh` 字段，但在组装 `positiveSegments` 时被遗漏，导致生成的关键帧只有景别和情绪词，没有具体的镜头画面内容（如雨夜道路、踩踏水洼、撑伞等）。此外，`_enqueueFrame` 遗漏了 `scene` 场景参数的提取与传递，且空镜头未加人脸负向抑制，导致生图大模型在无信息时随机绘制千篇一律的人物头像。

## Goals / Non-Goals

**Goals:**
- 在 `PromptAssembler` 中将分镜的动作描述和场景特征无缝纳入生图 Prompt；针对空镜头自动注入环境主体与防人脸负向词。
- 修复 `_enqueueFrame` 处的 `scene` 查找与传参漏洞。
- 确保有角色的镜头能够将角色设定的基础 Prompt 与参考垫图带入生图调用，维持角色一致性。

**Non-Goals:**
- 不在此变更中修改底层视频编码格式。

## Decisions

### 决策 1: 视觉动作描述（actionZh）进入 Prompt 组装链
- **方案**: 在 `PromptAssembler.buildShotPrompt` 中，将 `actionZh`（或其中的视觉主体特征）组装入 Prompt。主流商业生图模型（如 Agnes / FLUX / SD3.5 / DALL-E 3 / Midjourney）均对双语及视觉语义动作具有优秀理解力；同时支持直接将动作描述作为场景主体注入。
- **原因**: 画面动作（“阴影中的高大男子缓缓撑开黑伞”、“低角度拍摄雨点砸向地面”）是镜头视觉灵魂，绝不能在组装时被丢弃。

### 决策 2: 空镜头自动人物抑制机制
- **方案**: 当 `parts.character == null` 且分镜未指定登场角色时，自动在 negativePrompt 中附加 `person, human, face, character, people, man, woman, portrait`；并在正向词中强化场景环境词（如 `scenery, environment, establishing view, no people`）。
- **原因**: 彻底杜绝空镜头（如街道全景、水洼特写）被生图模型脑补塞入大头人脸。

### 决策 3: 场景卡传参对齐
- **方案**: 在 `storyboard_board.dart` 的 `_enqueueFrame` 中，根据 `shot.sceneId` 从 `scenes` 列表中解析出对应的 `SceneCard` 并传入 `ImageGenTask`。

## Risks / Trade-offs

- **[Risk]** 中文动作直接进入提示词是否会影响部分海外小模型的理解？
  - **Mitigation**: 当前已接入的 Agnes / 硅基流动等模型底层均为现代多模态/T5-XXL 编码器，原生支持中英混合语义；后续如需纯英文亦可通过轻量 Prompt 翻译桥接。
