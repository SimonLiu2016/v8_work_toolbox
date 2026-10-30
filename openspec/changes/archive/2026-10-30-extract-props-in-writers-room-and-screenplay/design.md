## Context

参见 `proposal.md`。当前代码库中：
1. 编剧研讨室（`WritersRoomDialog` & `AiConstraintEngine.extractWritersRoomMaster`）仅抽取角色、人物关系及宏观大纲，输出结构未定义 `key_props`，研讨室 UI 仅有角色同步至 IP 主库，缺少道具同步路径；
2. 剧本工作台（`ScreenplayPanel`、`NovelImportTaskService`）使用的核心模型 `DramaScene` 与 `DramaBeat` 无道具属性，Prompt 中未提示提取道具；
3. 下游 `StudioShot` 已具备 `propIds`、`ShotContinuity.holdingRight` / `holdingLeft`，且 Prompt 组装器已支持道具 `<Picture N>` 引用。

本设计聚焦于打通从小说原著解析（宏观研讨室 + 微观工作台）到 `PropCard` 及分镜 `StudioShot.propIds` 的全链路衔接。

## Goals / Non-Goals

**Goals:**
- 在 `_promptWritersRoomMasterExtract` 与 `_promptWritersRoomSeasonBeats` 中支持 `key_props` 结构化提取；
- 在 `WritersRoomDialog` 中新增关键道具查看面板，并支持一键批量写入 IP 主库（`PropCard(isKeyProp: true)`）；
- 在 `DramaBeat` 模型中新增 `props: List<String>`、`holdingItem: String`、`holdingHand: String`（默认持握右手或双手）以及序列化支持；
- 在 `_promptNovelDramaChapterAdaptation` 与 `_promptScreenplayGeneration` 中注入已知 IP 道具名，并要求在各节拍中输出道具与手持；
- 在 `ScreenplayPanel` 节拍视图中渲染道具 Chip，支持未入库即时道具一键收录为 `PropCard`；
- 在 `AiConstraintEngine.extractDramaBeatsToShots` 中自动将 `beat.props` 与项目道具库模糊匹配，填充 `StudioShot.propIds`，并根据手持信息填充 `ShotContinuity`。

**Non-Goals:**
- 不修改底层图像/视频生成引擎的 API 协议（已具备道具支持）；
- 不对剧本工作台解析出的所有琐碎即时道具强制全自动建卡入库，避免 IP 资产池被膨胀污染；
- 不改变已有剧集的历史分镜与剧本存储兼容性（旧数据字段缺失默认回落为空列表与空字符串）。

## Decisions

### Decision 1: 道具分层解耦与生命周期策略
- **决定**：
  - **宏观关键道具（Key Props）**：由编剧研讨室负责提取，属于全剧 IP 级资产，默认 `isKeyProp: true`，提供批量入库动作；
  - **微观使用道具（Beat Props）**：由剧本工作台负责提取到节拍（`DramaBeat`），涵盖 IP 关键道具的调用与即时生活/剧情道具（如茶杯、飞刀）。
- **考虑的替代方案**：
  - *替代方案 A*：剧本工作台每次解析出道具都自动写入 IP 主库。缺点是会导致 IP 道具库中充斥着“破碗”、“碎布条”等一次性低价值物品，管理成本急剧上升；
  - *替代方案 B*：仅在编剧研讨室做道具提取，剧本工作台不做。缺点是单集特有的关键剧情道具（如特定密信、毒药）无法在文学剧本与分镜中自动捕捉。

### Decision 2: 节拍级（DramaBeat）承载 vs 场次级（DramaScene）承载
- **决定**：选用节拍级（`DramaBeat.props`、`DramaBeat.holdingItem`、`DramaBeat.holdingHand`）。
- **理由**：
  - 影视分镜（`StudioShot`）是直接由 `DramaBeat` 1:1 或 1:N 映射而来的。如果只在场次级声明道具，生成单镜头时无法获知究竟是哪个镜头拿着道具、处于哪只手上；
  - 节拍级能够精确捕获诸如“反手掷出淬毒短刃”、“端起青花茶盏轻吹热气”的微动作与手持连贯性。
- **考虑的替代方案**：
  - *替代方案*：场次级定义 `scene.props`。缺点是下游拆镜仍需依靠规则猜镜头归属，容易出现道具穿越或动作与道具脱节。

### Decision 3: 道具名称到资产 ID 的智能模糊解析与容错
- **决定**：在由剧本转分镜（`extractDramaBeatsToShots`）时，通过 `propMap = {for (p in props) p.name.trim().toLowerCase(): p.id}` 进行不区分大小写的名字匹配；如果节拍道具包含道具卡全称或子串（如“墨大夫的玄铁短刃”与“玄铁短刃”），自动匹配该 `PropCard.id` 并注入 `StudioShot.propIds`。
- **理由**：大模型在生成动作或台词描述时，道具名称偶有定语修饰（如“淬毒短刃” vs “短刃”），轻量模糊匹配能显著提高自动化匹配率。

## Risks / Trade-offs

- **[Risk] Prompt 输出 Token 长度增长可能引起轻微解析延迟**
  - *Mitigation*: 仅在输出 JSON Schema 中增加必要的道具字段，并在研讨室与单章改编中限制 `key_props` 数量为 3~8 个最核心道具，确保不会触及模型最大输出截断。
- **[Risk] 向后兼容性问题（旧剧集 DramaBeat 无道具字段）**
  - *Mitigation*: `DramaBeat.fromJson` 对 `props`、`holding_item`、`holding_hand` 均设安全回退默认值（`const []` 与 `''`），确保旧数据加载与保存零破坏。
