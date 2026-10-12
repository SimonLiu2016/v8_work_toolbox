## Why

Dola 免费号池的模型 id（`dola-pool-seedance-2.0` / `dola-pool-seedance-2.5`）不在 `MediaCapabilityPresets.forModel()` 的内置声明里，因此能力查找一路落到 `MediaCapabilityDefaults.openai`——后者给出 `durations: [4,5,6,8,10,12,15]`。

免费版 Dola 实际只支持 **5 / 10 / 15 秒**三档。默认值里有 4、6、8、12 这些上游不接受的选项，用户选到时会被上游拒绝。同时 `supportsFirstFrame`、`maxReferenceImages` 也与事实不符——Dola 的 payload 只有 `text_block`，**没有任何图片输入通道**，而 openai 默认声明了 `supportsFirstFrame: true`、`maxReferenceImages: 1`。

目前不出错只因 `seedance2Video` 的时长集合与 openai 默认恰好一致，属巧合而非设计。

附带一个已存在的不一致：适配器里的 `durationSec.round().clamp(5, 30)` 与真实能力（5/10/15）不符，30 秒是上游会拒的值。

## What Changes

- 新增 `dolaVideo` 内置能力声明：`durations: [5, 10, 15]`、`supportsFirstFrame: false`、`maxReferenceImages: 0`、仅文生模式
- `forModel()` 识别 `dola-pool-` 前缀并归一到该声明（模型 id 形如 `dola-pool-seedance-2.5`）
- 适配器的兜底 clamp 从 `(5, 30)` 改为吸附到 5/10/15 中的合法值，与能力矩阵的意图一致
- 新增测试：声明命中、时长吸附（请求 4 秒 → 5 秒、请求 12 秒 → 15 秒）、图片能力被显式拒绝

不改 `_wrap` 的签名，不动其他适配器，不新增配置项。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `media-model-capability-matrix`：在「模型能力声明」中补充 Dola 免费号池的声明来源说明，并在「请求参数规整」中补一条 scenario——用户请求的时长落在两档合法值之间时的吸附方向。

## Impact

- **受影响代码**：`lib/services/media_capability.dart`（新增声明 + `forModel` 前缀归一）、`lib/tools/dola_pool/services/dola_pool_video_adapter.dart`（兜底 clamp）
- **行为变化**：走 Dola 号池的生成请求，时长被吸附到 5/10/15。此前若用户选 8 秒，会按 8 秒提交并被上游拒；现在按 15 秒提交并记录。分镜默认 3 秒——低于 5 秒下限，将按 5 秒提交
- **连带可见性**：`SegmentVideoGenTask` 会把 `submittedDurationSec` 写回数据层，Dola 路径的看板将开始显示「请求 3s / 实际 5s」这类差异
- **图片能力**：Dola 不支持首帧，意味着依赖关键帧首图的请求在 Dola 路径下会被显式拒绝——这是「不被支持的能力必须显式拒绝」要求的正确行为，用户看到明确提示而非静默降级
- **测试**：`test/media_capability_matrix_test.dart` 新增用例；Dola 现有测试需确认未依赖旧的 clamp 行为
