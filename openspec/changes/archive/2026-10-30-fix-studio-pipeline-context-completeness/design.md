## Context

三类上下文断裂各有不同的技术形态，但共用一个根因：**AI 调用的输入是从调用点临时拼装的，而不是从一个统一的上下文对象派生的**。每个调用点自己决定传什么，于是漏传、分裂、缓存失效都成为可能。

本设计逐类给出修正，并在最后一项（任务依赖）触及队列的调度模型。动机见 proposal.md — Why。

约束：`AssetBindingResolver` 已是素材指代的唯一来源（由 `unify-reference-material-binding-and-spatial-narrative` 建立），本设计的所有取材统一都向它收敛，不另建第二套。

## Goals / Non-Goals

**Goals:**
- 让每一个 AI 调用点的输入都可以被追问"你传了什么"并得到确定答案。
- 让生图与生视频对同一分镜的取材结果可证明一致。
- 让"字段变了但提示词没变"这件事在结构上不可能发生。
- 让同镜的图任务与视频任务有确定的先后，不靠并发槽抢占。

**Non-Goals:**
- 不合并四套视频提示词编译器（`buildVideoGenPrompt` / `buildSegmentPrompt` / `PhotorealisticPromptCompiler` / `SeedanceTaskCompiler`）——那是独立的大重构。
- 不建立 `scenes` / `screenplayText` / `synopsis` 的单一事实源。
- 不做 markdown → `DramaScene` 反向解析。
- 不做 >35000 字长文的分段提炼与角色属性增量富化。

## Decisions

### Decision 1: 拆镜入口统一到一个私有方法，而不是让两个面板互相调用

`ScreenplayPanel._breakdownWithAi` 与 `StoryboardBoard._breakdown` 当前各自拼 `ScriptContext`。修正方式：两者都改为构造**同一组**输入参数，调用同一个新增的私有辅助（或都直接调 `AiConstraintEngine.scriptBreakdown5D` 但用相同的取值优先级）。

输入优先级固定为：
```
synopsis  = screenplayText.trim().isNotEmpty ? screenplayText.trim() : ep.synopsis.trim()
scenes    = ep.scenes
contract  = ep.protectedContract
```

剧本工作台当前的 `_isRawTextMode` 分支保留（文本模式下取控制器内容），但取到的仍是同一份 `screenplayText` 语义。

替代方案：让 `StoryboardBoard` 直接调 `ScreenplayPanel` 的方法。否决——两个是独立的 StatefulWidget，跨 Widget 调用会把它们的生命周期拧在一起。

### Decision 2: `scriptBreakdown5D` 的节拍字段补传放在 `AiConstraintEngine`，不改 `ScriptContext`

`ScriptContext.scenes` 已经携带完整的 `DramaScene`（含 `beats`），信息本来就在内存里，只是 `scriptBreakdown5D` 组装 `scenesBlock` 时没读。所以修正只需改 `scriptBreakdown5D` 的 buffer 拼装，**不需要给 `ScriptContext` 加字段**。

节拍行的输出格式从
```
  * 节拍 ${b.id}: [${b.dramaticFunction}] ${b.name} - ${b.action}
```
扩展为按需追加各非空字段。

替代方案：给 `ScriptContext` 加一个 `List<DramaBeat> flattenedBeats`。否决——冗余存储，且 `scenes` 已经能推出它。

### Decision 3: `screenplayGeneration` 新增三个可选参数，不新建任务类型

签名扩展为接收 `characterProfiles`（`List<String>`，预先格式化的"姓名：容貌/服装"文本）、`sceneNames`（`List<String>`）、`protectedContract`。三者都有默认空值，既有调用点不受影响。

在 `AiConstraintEngine` 内格式化而非传 `CharacterCard` 列表——引擎层不应依赖 UI 的模型装载方式，且格式化规则（取哪些字段、截断到多少字）属于提示词工程，应与调用点解耦。

替代方案：让调用方传格式化好的整段文本。否决——格式化规则会散到多个 UI 文件，改一次提示词要改多处。

### Decision 4: `ImageGenTask` 改用 `AssetBindingResolver`，但保留其"形态三视图优先"的既有语义

`ImageGenTask._referenceImages` 当前有一层 `AssetBindingResolver` 没有的逻辑：**按 `characterVariations` 解析出的形态去找形态专属三视图**（`turnaround_<variationId>.png`）。这是生图路径的真实需求（不同形态要有不同参考图），丢掉它是回归。

所以 `AssetBindingResolver` 需要能接收一个可选的"形态解析器"，或 `ImageGenTask` 在调用前把解析出的形态写进一份临时的 `CharacterCard`（把 `activeVariation` 换成解析结果）。

选择后者：构造 `card.copyWith` 语义的临时卡传入 resolver。理由是不改 resolver 的签名——它是三条路径共用的唯一来源，签名变动会影响 `VideoGenTask` 与 `SegmentVideoGenTask`。

风险：临时卡的构造要在 `ImageGenTask.run` 里做，且必须与 UI 侧 `_resolveVariation` 的三级优先级（shot → episode override → active）一致。这条优先级目前只存在于 `storyboard_board.dart`，需要下沉为共享函数，否则生图路径与 UI 预览会漂移。

### Decision 5: 生图多图编号改为按实际参考图列表推导

`buildShotPrompt` 当前用 `effectiveCharacters` 下标 + `scene != null` 推断编号。改为：由调用方把**实际有序的参考图文件列表**（或从该列表推出的「哪些角色有图、场景有没有图」）传进 `PromptParts`，编号按这个列表的顺序生成。

`buildAgnesMultiImageDirective` 增加入参：`List<CharacterCard> charactersWithImages`（按参考图顺序）+ `bool hasSceneImage`（由调用方按实际是否有场景参考图传入）。`hasSceneImage` 参数当前已存在但恒为默认 `true`——这次真正接上。

`isMultiImage` 与 `hasCharacterReferences` 也改由调用方按实际列表长度计算，不再由 `PromptParts` 内部推断。

### Decision 6: videoPrompt 失效用"来源字段快照"而非时间戳比对

`StudioShot` 新增 `videoPromptSourceKey`（字符串），在写入 `videoPrompt` 时记录当时决定提示词的五个字段的拼接值（`actionZh` / `dialogue` / `characterIds` / `sceneId` / `assetBindings` 的稳定序列化）。生成前比对当前键与记录键，不一致即视为失效，走动态组装。

选择快照而非 `updatedAt`：`updatedAt` 在任何字段变更时都会变（包括改时长、改画幅），用它会误失效——用户只是调了时长却丢了定制提示词。

失效时**不删除** `videoPrompt` 字段，只在生成时忽略它，UI 显示"字段已变更，已回退自动组装"。删除是破坏性的（用户找不回来），忽略是可恢复的（用户改回字段或手动重存即可）。

替代方案：在 `_onShotEdited` 里检测五字段变更并清空 `videoPrompt`。否决——`_onShotEdited` 收不到"改了哪个字段"的信息，且清空不可逆。

### Decision 7: 任务依赖用「阻塞判定」而非「显式 DAG」

`StudioTask` 增加 `requiresTaskId: String?`。`_drain` 选取下一个可启动任务时，跳过所有 `requiresTaskId` 指向的任务仍处于非终态（或终态为 failed/cancelled）的候选项。

被依赖任务失败时，等待方 SHALL 被标记为 failed 并带明确错误（「前置任务未满足」），不进入 queued→running。

不建完整 DAG（多对多依赖、依赖图可视化）——当前需求只有"同镜先图后视频"一种形状，DAG 是过度设计。`requiresTaskId` 单字段足以表达，且未来若需扩展可平滑升级。

## Risks / Trade-offs

- **[形态优先级下沉为共享函数会触及 `storyboard_board.dart` 与 `studio_generation_tasks.dart` 两处]** → 下沉为 `StudioProjectManager` 或独立工具类的静态方法，两处都改为调用它；单测覆盖三级优先级的每一种组合。
- **[生图编号规则变化会让既有测试断言大面积失败]** → tasks 中显式列出 `test/ai_video_studio_prompt_assembler_test.dart:839` 这类需重写的断言。
- **[`ImageGenTask` 改用 resolver 后，取材结果可能变化，已生成的关键帧重跑时画面会变]** → 这是修正的预期效果（用户指定的素材终于生效），但需在任务的验证步骤中明确「画面变化是预期的」。
- **[任务依赖使批量生成的启动变慢（同镜的图必须先完成）]** → 不同分镜之间仍可并发（依赖是 per-shot 的），整体吞吐不下降；队列面板需把「等待前置」状态显示出来，否则用户以为卡住。
- **[videoPrompt 快照键的序列化若不稳定（如 Map 顺序），会误失效]** → `assetBindings` 序列化时按 key 排序；单测覆盖「只改时长不失效」与「改任一五字段即失效」。
- **[`_breakdown` 不回写 synopsis 的 UX 空洞]** → 该修正属于数据诚实性变更，本变更只负责输入源统一，不重复处理。

## Migration Plan

无需数据迁移：

- `videoPromptSourceKey` 缺失时视为空串，与当前任何非空 `videoPrompt` 都不匹配 → 首次生成时走动态组装一次并把键写回。这是安全的默认（等价于"旧的定制提示词先按字段校验一遍"）。
- `StudioTask.requiresTaskId` 缺失时为 null，行为与当前完全一致。
- `buildAgnesMultiImageDirective` 新参数有默认值，既有调用方式不破。

回滚策略：各修正点独立，可单独回退。

## Open Questions

- **批量生成时，同集多镜的图任务与视频任务如何交织？** 本设计按"逐镜入队（图→视频依赖）"推进，则队列里会是 `img1, img2, ..., imgN, vid1, vid2, ..., vidN`，依赖保证 `vid_k` 在 `img_k` 后。另一种是"全部图先入队，图都完成后再全部入队视频"——后者并发利用率更高但实现更复杂。本变更取前者（简单且正确），若实测吞吐不可接受再优化。
- **`ImageGenTask` 的形态解析优先级下沉后，`episode.variationOverrides` 这一级要不要保留？** 保留（与 UI 现状一致），但它与 `shot.characterVariations` 的优先级关系值得产品再确认一次——当前实现是 shot > episode > active，这个顺序没有 spec 依据。
