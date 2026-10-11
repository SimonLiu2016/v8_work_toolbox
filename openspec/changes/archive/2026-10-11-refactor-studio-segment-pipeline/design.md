## Context

现状与约束（实现细节见 proposal.md 的 Impact 与各 delta spec）：

- `StudioEpisode.shots` 是唯一的事实来源，`storyboard.json` 只有一个顶层 `shots` 数组；`StudioProjectManager` 的全部读写都围绕它。
- 视频生成路径的请求契约是 `VideoGenRequest{ inputImage: File, cameraMove, durationSec, shotNumber, outputFile }`——**单张首帧 + 运镜短语**，没有承载完整画面描述与多参考的位置。两个云端适配器（SenseAudio / Agnes）都把 `cameraMove` 当作 prompt 主体，且都写死了 `'ratio': '9:16'` 与 `clamp` 后的时长。
- `PromptAssembler.buildShotPrompt` 已有「段顺序即优先级、超限从尾部丢」的机制（`_joinWithinLimit` + `droppedSegments`），可直接复用到片段提示词。
- `StudioTaskQueue` 已支持并发上限、取消意图、流式状态与 `CancellableTaskRunner`，新增任务类型不需要改动调度核心。
- FFmpeg 合成、剪映导出、SRT/Ducking 全部按 `episode.shots` 顺序消费媒体路径，本设计必须保证它们的输入形状不变。

## Goals / Non-Goals

**Goals:**

- 让「片段」成为 `drama` 的视频生成单元，同时保持 `shots` 作为声音、字幕、合成的事实来源。
- 让连续性台账成为可注入、可校验、可追溯的一等字段，且用户编辑永远优先于 AI 推导。
- 旧版 `storyboard.json` 无损迁移，且迁移幂等。
- 视频请求契约扩展为「提示词 + 多参考图 + 时长」，但**不**在本变更内解决模型能力矩阵（那是 `borrow-toonflow-media-capability-matrix` 的职责）。

**Non-Goals:**

- 不引入 Toonflow 的 1406 行自然语言规则书；只落其可校验的结构化部分（片段边界、状态链、时长自洽）。
- 不改造 `AiConfigStore`、供应商预设或模型发现。
- 不改变 `anime` / `narration` 的默认策略语义（本地 Ken Burns），只允许按片段合并调用。
- 不做分镜拖拽重排（现有 UI 本就不支持，片段化不改变这一点）。

## Decisions

### 决策 1：`StudioSegment` 只存「元数据 + 指向」，不复制分镜

`StudioEpisode` 增加 `List<StudioSegment> segments`，其中

```dart
class StudioSegment {
  final String id;                 // seg-<n>
  final int targetDurationSec;
  final String boundaryReason;     // AI 给出的边界判定理由，用户可编辑
  final String promptZh;           // 系统组装/用户编辑的中文片段提示词
  final String? clipPath;          // 相对 segments/ 的文件名
  final SegmentStatus status;
  final List<String> shotNumbers;  // 指向 shots，按顺序
}
```

`StudioShot` 增加 `String segmentId` 与 `ShotContinuity continuity`。

- **备选 A：把分镜嵌进片段**（`StudioSegment.shots: List<StudioShot>`）。否决：会让 `shots` 从唯一事实来源变成投影，声音设计、SRT、合成、剪映四处消费方全都要改，且「同一分镜归属两个视图」会立刻出现同步问题。
- **备选 B：片段只作为运行时视图，不落盘**。否决：片段提示词与产物需要持久化，否则重开窗口即丢失；且无法满足「旧版迁移后写回」的 spec 要求。

### 决策 2：迁移放在 `StudioProjectManager.readEpisode`，而不是一次性写死

`fromJson` 时若无 `segments` 字段，按分镜顺序每 2–3 镜归入一段（`shotNumbers` 连续，最后一段可为 1 镜），`continuity` 取空对象。迁移结果**不立即写回**，保留到下一次 `saveEpisode` 自然落盘。

- **理由**：读取路径不该有写副作用（失败会污染用户数据，也让「打开即修改」难以解释）；幂等由「`segments` 存在即跳过」天然保证。
- **测试含义**：`test/ai_video_studio_segment_test.dart` 需要两条断言——「加载旧文件不产生磁盘写入」与「连续两次 save 后片段划分不变」。

### 决策 3：`VideoGenRequest` 增加可选字段而非新接口

```dart
class VideoGenRequest {
  final File? inputImage;              // 由必填改为可选：片段生成不依赖单张首帧
  final List<File> referenceImages;    // 新增，片段级多参考
  final String promptZh;               // 新增，完整画面描述；为空时回退 cameraMove
  final String cameraMove;
  final double durationSec;
  final int shotNumber;
  final File outputFile;
  final String productionType;
}
```

`inputImage` 改为可选是**有意的兼容破坏**：`KenBurnsVideoAdapter` 在 `inputImage == null` 时抛出明确的「本地动效需要首帧」错误，而不是静默产出黑帧。

- **备选 A：新增 `SegmentVideoGenRequest` 与 `SegmentVideoGenAdapter`**。否决：会让 `VideoGenAdapterFactory` 的选择逻辑翻倍，且 `drama` 与 `anime`/`narration` 的策略分发已经在 `productionType` 上做过一次，再加一层分发只会让「单镜覆盖」的判断散落两处。
- **备选 B：把 `promptZh` 塞进 `cameraMove`**。否决：两个字段语义不同（一个是完整分镜描述，一个是运镜短语），混用会让「用户只改运镜」这个现有交互产生不可预期的结果。

### 决策 4：多参考图在适配器内做「能力协商 + 优雅降级」

`SenseAudioVideoAdapter` 的 `content` 数组支持多个 image 项（现有协议就是数组），把 `role` 从 `first_frame` 改为按位置命名（第一张 `first_frame`，其余 `reference`）。
`AgnesVideoAdapter` 的 `keyframe` 模式只接受单张 `first_frame`，且官方禁止首帧与参考素材混用——因此它只能取**第一张**参考图，并在 `AiLogger` 里记录「N 张参考图被降级为 1 张」的警告。

- **理由**：不让「适配器不支持多参考」变成阻断项；降级必须可见（日志 + 片段上的 `degradedRefCount`），否则用户会以为一致性约束生效了。
- **不做**：不在本变更内为 Agnes 实现「把多张参考图预拼合成一张」的变通。那会引入新的画质损失且难以校验，留给后续。

### 决策 5：片段提示词由 `PromptAssembler.buildSegmentPrompt` 组装，AI 只给「剧本级」内容

AI 的 `scriptBreakdown` 产出片段边界的**理由**与每个片段的目标时长、涉及镜号；片段的最终提示词由 `buildSegmentPrompt` 从「分镜的 `actionZh`/`dialogue`/`continuity` + 角色卡 + 场景卡 + 风格词」确定性组装。

- **理由**：AI 直接写提示词会让「改了分镜字段但片段提示词没变」这类不同步必然发生（现有 `ImageGenTask` 已经为同样的问题在 `finally` 里重写 `assembledPrompt`）。确定性组装让「重算」变成纯函数，UI 不需要判断何时该重新生成。
- **代价**：AI 失去了对片段提示词的整体修辞控制。用 `boundaryReason` 与可编辑的 `promptZh` 覆盖字段补偿——用户/AI 可以显式追加片段级补充说明，该字段作为独立段参与 `_joinWithinLimit`。

### 决策 6：`continuity` 的注入位置在提示词尾部，但状态字段不参与超限丢弃

`buildSegmentPrompt` 的段序：质量基线 → 风格 → 片段目标时长 → 角色身份锚点（含 `{{ref N}}`）→ 场景锚点 → 逐镜动作/台词 → 运镜 → **连续性绝对状态** → 片段级补充说明。

`_joinWithinLimit` 现有行为是「从尾部丢」。连续性绝对状态被放在运镜之后、补充说明之前，并**从丢弃候选里排除**——丢风格只是难看，丢持物状态会直接产生穿帮。

- **理由**：这是本设计里唯一一处改动 `_joinWithinLimit` 语义的地方，需要显式记录。做法是给 `_JoinResult` 增加 `pinned` 参数（被钉住的段不进入丢弃候选），而不是复制一份拼接函数。

### 决策 7：`StudioTaskKind` 增加 `segment`，队列面板按 kind 分组

`enqueue` 的签名不变（`runner` 已经是一个接口），新增 `SegmentVideoGenTask implements StudioTaskRunner, CancellableTaskRunner`。它的取消检查点放在：提交前、轮询循环每轮、写回前——与 `VideoGenTask` 一致。

- **备选 A：给队列加「优先级」**。否决：当前没有「片段要先于分镜」的需求，引入优先级会让并发控制的推理变复杂。
- 并发上限共享同一配置（spec 已声明）；片段任务是长任务（分钟级），实测若发现它长期挤占生图任务，再考虑按 kind 分池——列为 Open Question。

## Risks / Trade-offs

- **[Risk] 云端模型不接受 12–15 秒时长或多参考组合** → 适配器层按模型声明的最小可生成单元拆段仍是必需的。本变更只把「请求契约」备好，实际可用的时长/参考数量由 `borrow-toonflow-media-capability-matrix` 提供矩阵后才能真正生效。在此之前，`SegmentVideoGenTask` 提交前做一次「目标时长是否在模型白名单」的检查，不在白名单则明确拒绝并提示，而不是 clamp 后静默提交。
- **[Risk] `inputImage` 改为可选后，既有测试与调用方漏改会在运行时才暴露** → `test/ai_video_studio_adapter_test.dart` 增加「片段请求不传 `inputImage` 时 Ken Burns 必须抛出可读错误」的断言；`flutter analyze` 的 `invalid_use_of_required_named_param` 之外，靠这条运行时断言兜住语义变化。
- **[Risk] 迁移规则（每 2–3 镜一段）与 AI 的片段划分不一致，用户会看到「同一集两次打开片段分组不同」** → 迁移只在 `segments` 缺失时发生一次，之后持久化；`boundaryReason` 对迁移生成的片段写死为「旧版数据自动分组」，让用户能区分。
- **[Risk] 单镜覆盖后片段生成范围变化，`shotNumbers` 与实际参与生成的镜号不一致** → 片段上增加 `excludedShotNumbers`，片段生成时跳过；`boundaryReason` 记录跳过原因。不做「自动重算片段时长」——那会让用户的确认状态失效。
- **[Risk] 连续性台账字段多，AI 输出 JSON 体积显著增大，`scriptBreakdown` 的解析失败率上升** → Schema 校验失败时的重试提示（现有 `retryHint` 机制）保留；同时把 `continuity` 的必填项压到最少（`worldPosition`、`holdingLeft`、`holdingRight` 必填，其余可空），降低单次输出的失败面。
- **[Trade-off] `promptZh` 由确定性组装意味着「AI 写的片段提示词」不存在了** → 用户失去一键获得整段润色提示词的能力。用片段级补充说明字段部分补偿；若后续证明需要，可在 Open Question 1 解决后再加。

## Migration Plan

1. 数据层先行：`studio_models.dart` 加字段与迁移，`StudioProjectManager` 增加 `episodeSegmentsDir` 与片段读写。此步骤完成后旧文件仍可正常打开（只是没有片段分组）。
2. `PromptAssembler.buildSegmentPrompt` 与 `_joinWithinLimit` 的 `pinned` 支持，附单测。
3. `AiConstraintEngine.scriptBreakdown` 两段化 + Schema 扩展，附契约测试。
4. `SegmentVideoGenTask` + 适配器多参考，附任务与适配器测试。
5. `StudioTaskQueue` 的 `segment` kind + 队列面板分组。
6. `storyboard_board.dart` 的「按片段」视图与片段级操作。
7. 回归：`test/ai_video_studio_*` 全绿 + 手工验证一个旧剧集打开后分组稳定、合成产物不变。

回滚策略：数据字段全部为新增且带默认值，回滚代码后旧文件仍可被旧版读取（旧版忽略未知字段）；已生成的 `segments/*.mp4` 成为孤儿文件，由 `slimmer` 的孤儿检测或用户手工清理，不需要迁移脚本。

## Open Questions

1. **是否需要「AI 润色片段提示词」模式？** 本设计采用确定性组装，用户只能在 `promptZh` 里追加补充说明。如果实际使用中发现确定性组装的片段提示词在长片段上可读性不足，可能需要引入一个可选的 `segmentPromptPolish` AI 任务。这会增加一个 `StudioAiTask` 与一次网络调用，但不改变已定的数据结构，可在实现后评估。
2. **片段任务与生图任务是否需要分池？** 片段生成是分钟级长任务，与生图共享并发上限时可能让看板的关键帧长时间不动。当前无实测数据，按 spec 共享上限实现；若手工验证时发现明显挤占，再改为按 kind 分池（改动局限在 `StudioTaskQueue._drain`，不影响其他模块）。
