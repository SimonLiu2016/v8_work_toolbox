## Why

`VideoGenAdapterFactory.create()` 的五条返回路径里，只有「显式指定 `preferredEngineId`」这一条经过能力规整（`_wrap` → `NormalizingVideoAdapter`）。走系统 video 槽位、drama 回退 Kling、Dola 免费号池这三条路径返回的是裸适配器——请求参数不会吸附到模型能力范围内。

`NormalizingVideoAdapter` 的注释已经预言过这个后果：漏一次规整的 bug「只在特定模型上出现，测试很难覆盖到」。现在漏洞不在适配器里，而在工厂的分支上，且系统槽位正是日常最常走的路径。

## What Changes

- `create()` 的三条未包装路径补齐 `_wrap`，使所有非本地适配器都经过能力规整
- 走系统 video 槽位时把 `provider` 一并传给 `_wrap`，让能力矩阵优先用用户自己声明的模型参数，而不是落到协议级保守默认
- 新增一条遍历型回归测试：断言 `create()` 的每条返回路径（按不同输入触发）都不返回裸适配器
- 明确「本地 Ken Burns 不包装」这一既有设计，并为其补上测试，防止后来者误以为是漏包

不改变任何适配器的行为，不新增配置项，不调整 `_wrap` 的签名。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `media-model-capability-matrix`：补充一条 requirement，把「规整必须覆盖工厂的所有返回路径」从实现细节提升为契约。现有「请求参数规整」只说了规整规则本身，没有任何一条要求约束它在什么范围内成立——这正是三条路径能长期漏包的原因。

## Impact

- **受影响代码**：`lib/tools/ai_video_studio/services/video_gen_adapter.dart` 的 `VideoGenAdapterFactory.create()` 与 `_wrap()`
- **行为变化**：走系统 video 槽位 / drama 回退 / Dola 号池的生成请求，参数开始被规整。用户请求 15 秒而模型只支持到 12 秒时，将按 12 秒提交并在日志中记录——这是本 change 的意图，不是回归
- **连带影响**：`SegmentVideoGenTask` 会把 `submittedDurationSec` 写回数据层，因此这些路径的看板会开始显示「请求 15s / 实际提交 12s」的差异，此前它们不显示
- **测试**：`test/media_capability_matrix_test.dart` 新增用例；新增的遍历型测试在修改前为红、修改后转绿
- **不涉及**：Dola 账号池 UI 接线（另属分批计划，本 change 不触碰）
