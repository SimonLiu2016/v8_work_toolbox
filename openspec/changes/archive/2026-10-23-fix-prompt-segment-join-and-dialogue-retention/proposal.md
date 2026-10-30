## Why

上一轮 change（`fix-shot-causality-inversion-in-video-prompts`）引入片段级时序序列后，拼段逻辑留下两处未收尾的缺陷：

1. **块结构段与单行段的边界判错**。`_joinSegments` 只判断「前一段是否多行」，导致多行时序块会紧接在单行段同一行尾（`scene: ancient tavern <Picture 2>, [0.0s - 4.0s] 镜号 1：`），而多行块之后的单行段又会粘在块的最后一行上（`  对白：快躲开！, 声音与画面约束：…`）。可读性归零，且模型难以区分段边界。
2. **负向词拼接口径被意外改变**。同一处 `_joinSegments` 也被 `buildShotPrompt` 的负向词列表复用，导致 `person, human, face` 变成 `person\n\nhuman\n\nface`，破坏了空镜人物抑制负向词的完整性（`test/agnes_studio_pipeline_test.dart` 因此红）。

此外，上一轮 change 落下了两处**未同步的既有断言**：`test/ai_video_studio_prompt_assembler_test.dart` 中「剥离对白台词与剧本标头」与「目标时长不泄露进提示词文本，动作自然整合」两条测试仍断言旧行为（对白被剥离、动作用逗号平接），而 spec 已改为「保留对白并输出时序序列」。

## What Changes

- `_joinSegments` 的段边界判据从「只看前一段是否多行」改为「前一段或本段含换行」——块结构段前后都断行，单行段之间仍用「, 」。
- 同步上一轮 change 遗留的两条既有断言，使其反映「对白保留为时间区间内的配音行」与「时间区间分行呈现」的新契约。
- 不改变任何生成行为、协议或数据字段，纯属拼装口径与测试同步。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `ai-video-studio/segment-production`: 「片段提示词组装」的呈现要求补一句——时序序列段与相邻段之间 SHALL 以换行分隔，SHALL NOT 粘在同一行。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/prompt_assembler.dart` — `_joinSegments` 边界判据。
- `test/ai_video_studio_prompt_assembler_test.dart` — 两条既有断言的措辞与期望同步。

**风险**
- 极低。改动只影响提示词的段间分隔符与两条测试断言，不影响任何提交给模型的语义内容（换行与逗号对模型都是分隔）。
