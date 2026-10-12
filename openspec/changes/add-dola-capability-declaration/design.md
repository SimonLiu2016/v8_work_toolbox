## Context

Dola 的两个模型 id 是 `dola-pool-seedance-2.0` 与 `dola-pool-seedance-2.5`（由 `DolaPoolVideoAdapter.id` 拼出 `'dola-pool-$_model'`）。它们不在 `forModel()` 的 switch 里，所以走 `MediaCapabilityDefaults.openai`。

免费版 Dola 的真实能力（用户确认）：时长只支持 5 / 10 / 15 秒；请求体只有 `text_block`，没有任何图片输入通道。

适配器里现有的 `durationSec.round().clamp(5, 30)` 是兜底，与真实能力不符——30 秒上游会拒。

## Goals / Non-Goals

**Goals**

- 让 Dola 的能力可查、可规整，不再靠「与 openai 默认恰好一致」侥幸正确
- 让适配器的兜底 clamp 与能力矩阵意图一致

**Non-Goals**

- 不接入 Dola 的图片能力（免费版没有）
- 不改 `forModel()` 的调用方
- 不给 Dola 加 provider 概念（它没有供应商配置，是内置号池）

## Decisions

### 决策 1：`forModel()` 用前缀归一，而不是枚举两个完整 id

Dola 的模型 id 由适配器拼出，形如 `dola-pool-seedance-2.5`。枚举两个完整 id 也能work，但前缀归一更稳：将来 `_model` 换成 `seedance-3.0` 时不用改这里。

```dart
// 前缀命中优先于完整 id 匹配
if (modelId.startsWith('dola-pool-')) return dolaVideo;
```

放在 switch **之前**，因为 switch 的 default 会吞掉未枚举的值。

### 决策 2：`maxReferenceImages: 0` 而不是 1

Dola 的 payload 只有 `text_block`，没有图片输入通道。声明 1 会让调用方以为「传一张也行」，然后把第一张参考图当首帧塞进去——上游直接忽略或报错。

声明 0 让「不被支持的能力必须显式拒绝」这条 spec 要求能真正生效：携带参考图的请求在 Dola 路径下被拒，用户看到明确原因。

代价是**片段级生成在 Dola 路径下不可用**——它按设计要携带角色与场景参考图。这是正确行为而非缺陷：免费号池本来就不该驱动需要资产一致性的片段生产。用户会看到拒绝提示，可以切到其他引擎。

### 决策 3：适配器兜底改为吸附到合法档位，而不是 clamp

`clamp(5, 30)` 会把 8 秒变成 8 秒（在范围内），而上游只认 5/10/15。改成吸附：

```dart
// 取不超过请求值的最大合法档位；3 秒 → 5 秒（无更小档位可取最小）
final legal = const [5, 10, 15];
```

这其实是重复实现了一遍规整逻辑。更干净的做法是让适配器不兜底、完全依赖 `_wrap` 的规整——但适配器也可能被单独使用（不经工厂），留一层兜底更安全。两层一致就不会互相打架。

### 决策 4：分镜默认 3 秒会被抬到 5 秒，这是可接受的

`StudioShot.durationSec` 默认 3，低于 Dola 下限。规整会抬到 5 秒并记录。

不为此特殊处理：能力矩阵的规则是「不存在不超过请求值的合法时长时取最小合法时长」，对 3 秒请求取 5 秒是规则的直接应用。用户在看板上会看到「请求 3s / 实际 5s」，这正是 `submittedDurationSec` 的设计用途。

## Risks / Trade-offs

- **[Risk] 片段级生成在 Dola 路径下被拒，用户可能以为是 bug** → 拒绝提示必须说清原因（「该引擎不支持参考图」）并指向可切换的引擎。实现时确认错误文本来自能力矩阵的显式拒绝，而非上层泛泛的「生成失败」。
- **[Risk] 兜底与规整两层逻辑重复，将来改一处忘另一处** → 用测试同时覆盖两条路径：直接调适配器（走兜底）、经工厂（走规整），断言两者结果一致。
- **[Trade-off] 前缀归一让 `forModel()` 多一条非 switch 分支** → 接受。换来的是 `_model` 变化时无需同步修改，且分支顺序（前缀优先）在代码里是一行注释能说清的。

## Migration Plan

纯增量，无数据迁移、无配置变更。

1. `media_capability.dart` 加 `dolaVideo` 声明 + `forModel` 前缀归一
2. `dola_pool_video_adapter.dart` 兜底改为吸附合法档位
3. 测试：声明命中、两档吸附方向、图片能力拒绝、兜底与规整一致
4. 跑 `media_capability_matrix_test` / `video_adapter_factory_wrapping_test` / 三个 dola 测试
5. 全量回归 + `dart analyze`
6. `./scripts/deploy_local.sh`

回滚：revert 单 commit，无持久状态。

## Open Questions

（无）
