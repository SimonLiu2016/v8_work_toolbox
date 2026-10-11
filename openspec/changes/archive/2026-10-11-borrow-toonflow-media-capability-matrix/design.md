## Context

现状与约束（实现细节见 proposal.md 的 Impact 与各 delta spec）：

- 四个视频适配器各自 clamp：`KenBurnsVideoAdapter`（本地，无外部约束）、`KlingVideoAdapter`、`SenseAudioVideoAdapter`（`ratio: '9:16'`、`resolution: '720p'` 写死，时长 `clamp(4,15)`）、`AgnesVideoAdapter`（`aspect_ratio: '9:16'` 写死，时长 `clamp(4,12)`）。
- 图像侧已有一次针对性修复：`SenseAudioImageAdapter` 内置了分辨率白名单吸附（`integrate-senseaudio-image-generation`），但它是**适配器私有**的逻辑，其他图像适配器没有同类保护。
- `AiProviderConfig` 已按能力槽位分列模型列表（`videoModels` / `imageModels`），每个模型目前只是一个字符串 id。
- `AiLogger` 已存在并被视频适配器接入（`add-studio-task-error-log-viewer-and-fix-video-frame` 引入），吸附记录可复用该通道。
- 本变更依赖 `refactor-studio-segment-pipeline` 先落地，因为它同时改 `VideoGenRequest` / `ImageGenRequest`。

## Goals / Non-Goals

**Goals:**

- 把「模型支持什么」从适配器内部的魔法常量变成可声明、可查询、可测试的数据。
- 请求提交前一次规整，吸附与拒绝都留痕。
- 保守默认值让未声明的模型也能安全工作，且用户能区分「声明的能力」与「猜的默认」。

**Non-Goals:**

- 不从供应商 `/models` 端点动态拉取能力（需要每家返回结构化能力字段，目前只有 id/label）。
- 不改造 `AiConfigPage` 的候选编辑交互（只在其数据模型上扩展可选字段）。
- 不为本地 `KenBurnsVideoAdapter` 引入矩阵（它没有外部约束，写死 1080×1920 是其规格）。

## Decisions

### 决策 1：能力挂在「provider + model」二元组上，不挂在 provider 上

```dart
class MediaModelCapability {
  final List<String> modes;                 // text / singleImage / startFrameOptional / endFrameOptional / imageReference / videoReference / audioReference
  final List<int> durations;                // 秒，视频用
  final Map<int, List<String>> durationResolutions; // 时长 → 可用分辨率；缺省按所有时长通用
  final List<String> resolutions;
  final List<String> ratios;                // "9:16"
  final int maxReferenceImages;
  final bool supportsFirstFrame;
  final bool supportsLastFrame;
  final bool supportsNativeAudio;
  final bool isDeclared;                    // false = 协议级保守默认
}
```

存储形态：`AiProviderConfig` 增加 `Map<String, MediaModelCapability> mediaCapabilities`，键为模型 id。

- **备选 A：把能力塞进 `videoModels` 字符串列表（如 `"seedance-2.0|4-15|480p,720p"`）**。否决：字符串协议难以演进，解析错误会静默产生错误能力，且 `AiConfigPage` 直接把这些字符串展示给用户。
- **备选 B：新建独立的 `media_capabilities.json` 配置文件**。否决：能力与供应商配置同生命周期（换 Key、换模型时一起变），分开两个文件会让「删了供应商但能力还在」这类孤儿状态必然出现。
- **权衡**：`ai_config.json` 会变大。但一份能力声明是几百字节，供应商数量级下可忽略。

### 决策 2：吸附方向「取不超过请求值的最大合法值」

时长吸附向下取整（请求 15s、支持 4–12 → 12s），而不是四舍五入（可能到 15 → 被拒）或向上取整（用户要 5s 给 8s，成本与预期都错）。

分辨率/比例吸附按**比例距离**取最近：请求 1080×1920（9:16）而白名单是 1152×2048 / 864×1536，取比例差更小的一方。

- **理由**：向下取整保证「不超过用户预期」这一条不可破坏的期望；比例距离保证构图不突变。
- **备选 A：向上取整到最近合法值**。否决：会让 5 秒的请求变成 8 秒，用户为没要求的时间付费。

### 决策 3：拒绝与降级是两件事，必须分开

| 情形 | 处理 |
|---|---|
| 参数超范围（时长/分辨率/比例/参考数量） | 吸附 + 日志 |
| 能力维度不支持（无参考图能力却带参考图、不支持首帧却指定首帧、模式不在集合内） | **拒绝** + 可读原因 |

- **理由**：降级是「你的要求我打折满足」，拒绝是「你的要求我做不到」。把后者也降级会让用户在毫不知情的情况下得到一个完全不同的产物——例如把带角色参考的关键帧静默改成纯文生图，角色一致性直接丢失且无从察觉。
- 这条与 Toonflow 的 `canvasExecution.md` 一致：「不能自行降分辨率、缩时长、换模型/模式、删除参考或改变声音来『跑通』」——但注意那条针对的是**用户已确认后**的执行阶段，而这里的吸附发生在**提交前**，属于把用户请求翻译成模型能接受的形式，两者不冲突。

### 决策 4：`AiService` 之外新增独立的 `MediaCapabilityResolver`

解析器是纯函数式的：`resolve(providerId, modelId) → MediaModelCapability`，内部查 `mediaCapabilities`，未命中则按 `AiProtocolType` 取保守默认（openai → 4–12s / 单参考 / 无尾帧；agnes → 4–12s / 单首帧；未知 → 最短时长 + 无参考）。

放在 `lib/services/` 而不是工坊内：`ops_tool`、`reader` 等工具未来也可能消费媒体槽位，能力解析不该是工坊私有的。

- **备选 A：作为 `AiConfigStore` 的方法**。否决：`AiConfigStore` 已经是 300+ 行的配置容器，再把解析与默认值策略塞进去会让它同时承担存储与策略两个职责。
- **测试含义**：`test/media_capability_matrix_test.dart` 直接测纯函数，不需要 Keychain 或 HTTP。

### 决策 5：规整放在适配器基类之前的一层，而不是每个适配器里

新增 `MediaRequestNormalizer`（同样在 `lib/services/`），由 `VideoGenAdapterFactory.create` / `ImageGenAdapterFactory.create` 返回的适配器**包装**：

```dart
class NormalizingVideoAdapter implements VideoGenAdapter {
  NormalizingVideoAdapter(this._inner, this._capability);
  // generateVideo 先规整 request，再委托 _inner
}
```

- **理由**：四个适配器各自的 payload 构造差异很大，但规整逻辑完全相同。包装让新适配器自动获得规整，不需要每个作者记得调用。
- **备选 A：在每个适配器的 `generateVideo` 开头调用 `normalize(request)`**。否决：依赖人工遵守，且 `AgnesVideoAdapter` 的 `isKeyframe` 分支会让人搞错规整的时机（必须在 `dataUri` 构造之前还是之后）。
- **代价**：多一层委托，`VideoGenAdapter` 的运行时类型不再是具体适配器——`forceLocalKenBurns && adapter is! KenBurnsVideoAdapter` 这类判断会失效。缓解：包装类暴露 `unwrap()`，并在 `SegmentVideoGenTask` 中改用 `unwrap()` 后再做类型判断。

## Risks / Trade-offs

- **[Risk] 保守默认过松，让真实不支持的参数被提交** → 默认值取「最不容易被拒」的组合（最短时长、最低分辨率、单参考、无尾帧、无原生音频）。代价是未声明模型的画质/时长偏低；用 `isDeclared: false` 让 UI 明示「默认能力，未经确认」，引导用户补充声明。
- **[Risk] `durationResolutions` 的「按时长区分分辨率」在 UI 上难以表达** → 设置页只展示「时长集合」与「分辨率集合的并集」，详情由日志与错误提示补充。不做完整的二维矩阵编辑器。
- **[Risk] 吸附让用户误以为参数生效了** → 每次吸附必须入日志；分镜看板的生成结果区展示「本次提交的实际参数」（时长/分辨率/参考数），与用户请求值并列。
- **[Risk] 包装层破坏 `is` 类型判断** → 见决策 5 的缓解；`test/ai_video_studio_adapter_test.dart` 增加「`unwrap()` 返回内层适配器」的断言。
- **[Trade-off] 能力声明是静态的，供应商上线新模型或改参数范围后不会自动更新** → 本变更不解决；预设更新随版本发布。若后续需要，可在 `AiConfigPage` 加「手动编辑该模型能力」的入口（数据模型已支持，只是不做 UI）。

## Migration Plan

1. `MediaModelCapability` + `MediaCapabilityResolver` + 保守默认，附纯函数测试。
2. `AiProviderConfig` 增加 `mediaCapabilities` 字段与序列化（缺省空 map），`fromJson` 兼容旧文件；`test/ai_config_test.dart` 增加序列化断言。
3. `MediaRequestNormalizer` 与两个 Factory 的包装；`unwrap()`；既有适配器测试改造。
4. 为 SenseAudio / Agnes 的内置模型填入声明（来自两家文档与 spike 实测）。
5. `ImageGenRequest.referenceImages` 扩展与三个图像适配器改造；`studio_generation_tasks.dart` 读取多张参考图。
6. `AiLogger` 记录吸附/降级；设置页与看板展示能力摘要与实际提交参数。
7. 回归 + 手工验证一次「请求 15s 被吸附为 12s」的端到端路径。

回滚策略：`mediaCapabilities` 为新增可选字段，回滚后旧配置仍可读（新字段被忽略）；规整层撤销后行为回到写死 + clamp 的旧状态，不丢数据。

## Open Questions

1. **Kling 的能力声明从哪来？** 现有 `KlingVideoAdapter` 是硬编码的 `kling-v1` + `mode: 'std'` + `duration: '5'`，没有可信的官方能力文档来源。倾向做法：先给一个基于现有代码行为的保守声明（5s、std、单首帧），标注为未确认，待用户实测后再校准。这不会阻塞实现，但需要用户配合验证。
2. **是否需要「手动编辑模型能力」的 UI？** 数据模型支持，但本变更不做编辑器。若预设声明与实际情况不符而用户无法自行修正，会回到「只能靠日志发现」的老路。可在实现后根据反馈决定是否补一个高级设置入口。
