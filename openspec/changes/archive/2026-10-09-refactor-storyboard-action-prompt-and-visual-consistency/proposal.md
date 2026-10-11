## Why

在 AI 视频工坊的「分镜看板」中点击“关键帧”时，生成的图片没有结合分镜中的画面动作或场景背景，且无论空镜头还是剧情镜头均随机生成一个人物，跨镜头的角色长相完全不一致。
根因分析显示：
1. **动作描述缺失**：分镜拆解出的画面动作（`action_zh`）未被翻译并组装入生图 Prompt，AI 视觉模型只接收到了泛化的景别词，只能随机绘制肖像人脸。
2. **场景关联断裂**：关键帧任务（`ImageGenTask`）在分镜看板入队时遗漏了 `scene` 场景参数，且场景卡缺少视觉环境提示词。
3. **空镜头与角色一致性未区分**：没有登场角色的空镜头未注入负向人脸抑制词；有角色的镜头在角色卡未配置外貌词和参考图时缺少兜底人设锚定。

## What Changes

- **动作与画面翻译组装**：
  - 在 `PromptAssembler` 中将分镜的视觉画面动作描述加入组装链；
  - 增加轻量级 Prompt 视觉转换/组装逻辑，将分镜动作（`action_zh`）转化为视觉提示词进入 Prompt，确保模型按故事动作（如“雨夜街头撑伞”、“水洼脚步溅水”）绘制画面。
- **场景链路修复**：
  - 在 `storyboard_board.dart` 的 `_enqueueFrame` 中补齐 `scene` 关联参数传递；
  - 场景卡增加默认环境提示词支持，并在空镜头中自动强化环境主体。
- **空镜头人物抑制与角色特征锁定**：
  - 当分镜无角色（空镜头）时，生图负向 Prompt 自动注入 `person, human, face, character` 等人脸抑制词；
  - 当分镜关联角色时，确保角色外貌特征（或参考垫图）被稳定注入。

## Capabilities

### New Capabilities
- `storyboard-visual-composition`: 规定分镜关键帧生成时的完整视觉组装契约，涵盖【动作环境融合】、【空镜头人物抑制】以及【角色视觉锚定】。

## Impact

- `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 支持 `actionZh` 视觉动作词组装与空镜头抑制。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: 确保 `scene` 与 `actionZh` 被正确传入 PromptAssembler。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 修复 `_enqueueFrame` 的场景关联查找与传参。
