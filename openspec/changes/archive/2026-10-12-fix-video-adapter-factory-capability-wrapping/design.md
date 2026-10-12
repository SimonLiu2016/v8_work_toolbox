## Context

`VideoGenAdapterFactory.create()` 有五个返回路径，但只有第一条经过能力规整。`_wrap` 的注释已经解释了为什么用包装而不是让各适配器自己调用规整——「漏一次的后果是这个模型的参数没被吸附，而这种 bug 只在特定模型上出现，测试很难覆盖到」。现在漏洞出现在工厂侧。

一个额外发现：走系统 video 槽位的路径手里就拿着 `provider`，却没有传给 `_wrap`。而 `_wrap` 的签名早就支持 `provider:` 参数，`MediaCapabilityResolver.resolve(provider, modelId)` 能用用户自己声明的能力，比落到 `MediaCapabilityDefaults.openai` 那套通用默认准得多。所以这不只是漏包，是漏包加漏传。

## Goals / Non-Goals

**Goals**

- 让规整覆盖 `create()` 的全部非本地返回路径
- 让走系统槽位的路径用上供应商声明的模型参数
- 用一条测试把「每条路径都要包」这个规则钉住，使新增分支漏包时立刻可见

**Non-Goals**

- 不重排 `create()` 的控制流（见决策 1）
- 不给 `KlingVideoAdapter` / `DolaPoolVideoAdapter` 增加 provider 概念
- 不改 `_wrap` 的签名
- 不触碰 Dola 账号池的 UI 接线（另属分批计划）

## Decisions

### 决策 1：在各分支处补 `_wrap`，而不是收单一出口

**方案 A（采用）**：三条路径各自 `return _wrap(...)`，共 3 处。

**方案 B（不采用）**：把 `create()` 改成「选出适配器 → 统一出口包装」。

```
create() {
  VideoGenAdapter chosen = _choose(...);   // 各分支只负责选
  return _wrap(chosen, modelId, provider: provider);
}
```

不选 B 的原因是它会碰到一个语义不匹配：`SenseAudioVideoAdapter.id` 返回的是 `'senseaudio-$_providerId'`，`AgnesVideoAdapter.id` 返回 `'agnes-$_providerId'`——**是引擎 id，不是 modelId**。单一出口只能拿到 `adapter.id`，拿不到 `doubao-seedance-2-0-260128` 这个模型名，`MediaCapabilityPresets.forModel()` 会直接落空。

要用 B，就得把 modelId 从各分支一路提到方法级，`provider` 也得跟着提（它现在在循环里，出了循环就没了）。这是控制流重写，不是补三行。

**真正的问题不是有几处 return，而是新分支的作者能否看见规则**——这个用测试解决比用结构解决更直接（见决策 2）。

### 决策 2：用遍历型回归测试防漏包，而不是依赖结构保证

新增一条测试，按不同输入触发 `create()` 的各条路径，断言每条都不返回裸适配器。

这条测试在修改前是**红**的——它断言的正是缺失的东西。红一次，规则就钉住了；以后谁加分支忘了包，测试立刻告诉他。

`NormalizingVideoAdapter` 注释里担心的「只在特定模型上出现、测试很难覆盖」，正适合用一条遍历型测试一劳永逸。

### 决策 3：本地 Ken Burns 的排除要被显式断言

`_wrap` 里 `if (adapter is KenBurnsVideoAdapter) return adapter;` 是既有设计——它的上界来自 `totalFrames.clamp(30, 900)`，本来就不该被媒体模型的能力矩阵裁剪。

但这一行在遍历型测试里会被误判为「漏包」。所以测试要**把这条排除也断言出来**，让后来者知道它不是疏漏。否则下一个人很可能"顺手修好"它，让 narration 类型想要 40 秒片段的合理请求被拒。

### 决策 4：`provider` 只在拿得到时传

分支 2 的 `provider` 在循环内，`provider.id.isEmpty` 的候选已被 `orElse` 过滤掉，所以进到 `_wrap` 时它一定是有效的。分支 3（Kling）、分支 4（Dola）没有 provider 概念，传 null，`_wrap` 回落到 `MediaCapabilityPresets.forModel(modelId)`。

这符合 spec 新增的那条 scenario「优先使用供应商声明的模型参数；无法取得时回落到协议级保守默认」。

## Risks / Trade-offs

- **[Risk] 行为变化被当成回归** → 走系统槽位/Dola 的生成请求，参数开始被规整。用户请求 15 秒而模型支持到 12 秒时按 12 秒提交。这是本 change 的意图，但 `SegmentVideoGenTask` 会把 `submittedDurationSec` 写回数据层，这些路径的看板会**开始显示**「请求 15s / 实际 12s」的差异，此前不显示。需在 proposal 的 Impact 里说明（已写）。
- **[Risk] 测试触发真实网络** → `create()` 内部会调 `adapter.isAvailable()`，Kling 与 Dola 都打真实端点。测试须复用项目既有的 `TestKeychainBridge` 与 `AppPaths.overrideRootForTesting`，并优先用 `preferredEngineId` 精确触发各分支，避免依赖网络探测的结果。
- **[Trade-off] 方案 A 留了五处 return** → 接受。等哪天真要给 Kling 加 provider 概念、或 `create()` 分支再多几个，方案 B 的动机才成立。

## Migration Plan

纯代码修正，无数据迁移、无配置变更。

1. 补三处 `_wrap`，其中分支 2 一并传 `provider`
2. 写遍历型回归测试，先确认它为红
3. 跑 `test/media_capability_matrix_test.dart` 与 `test/studio_settings_sync_test.dart`（后者断言过 `unwrap()` 后的具体类型，是最可能被波及的）
4. 全量回归 + `dart analyze`
5. `./scripts/deploy_local.sh`

回滚：revert 单个 commit 即可，无持久状态。

## Open Questions

（无）
