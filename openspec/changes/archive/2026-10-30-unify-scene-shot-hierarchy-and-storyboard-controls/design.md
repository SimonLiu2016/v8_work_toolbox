## Context

当前 AI 漫剧工坊在分镜制作与视频生成管线中存在层级混淆与逻辑冲突。现有系统在时空场次（`DramaScene`）与视听分镜（`StudioShot`）之间引入了人造的中间层 `StudioSegment`（大段），并强加 12 秒硬上限。这导致：
1. 单镜包含独立台词与动作（建议时长 4~8s），场内多镜相加必然超出 12 秒。云端视频模型无法在单次 10 秒调用中完成多机位、多动作的切换，导出时等分切片导致严重音画错位与动作溶烂。
2. 剧本拆镜逻辑仅将抽象场次编号（`SC001`）写入分镜 `sceneId`，未能映射至 IP 场景库中真实的 `SceneCard`（`scene_xxx`），导致七方位空间解构与参考图丢失。
3. 角色卡仅支持名字简单包含匹配，丢失“姜七少”、“少东家”等原著代称与绰号。
4. 分镜看板缺乏整集清空、从剧本重拆、单镜删除与插入等全生命周期控制。

详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- **两级影视体系统一**：大段语义与时空场次（`DramaScene`）严格对齐，时长为场内分镜时长之和，无 12 秒上限；小段明确为单镜头（`StudioShot`），作为 2~12 秒的 AI 视频生成原子物理单元。
- **强延续性接力生成**：场次内分镜支持顺序批量入队生成，依托已有首尾帧接力（First-Last Frame Relay）机制确保场内角色与光影绝对连贯。
- **全生命周期分镜管理**：分镜看板支持「一键清空本集分镜」、「从剧本重新拆解生成」（带防误触确认弹窗），以及单镜「删除镜头」、「在此镜后插入新分镜」，自动维护 1..N 连续镜号与场次总时长。
- **场景资产与角色智能关联**：剧本拆镜与分镜映射自动匹配真实的 `SceneCard`（`scene_xxx`），出场角色支持别名（`aliases`）与代称智能识别。
- **交付合成 1:1 精确对齐**：导出时间轴直接取单镜实际视频与建议时长，消除片段等分除法。

**Non-Goals:**
- 不删除底层 JSON 文件的 `segments` 键，保持磁盘存储兼容与旧工程加载稳定性，而是在语义与数据上将其与 `DramaScene` 1:1 对齐。
- 不引入重型外部 NLP 实体识别模型，角色别名识别依托规则引擎与角色卡扩展字段完成。
- 不修改底层视频模型 API 协议，仅改变调度与入参粒度。

## Decisions

### Decision 1: 场次与镜头两级数据模型映射（Scene ➔ Shot）
- **选择**：废除人造的 3 镜一组机械划分。在 `AiConstraintEngine.convertScenesToShots` 与剧本转分镜逻辑中，每个时空场次（`DramaScene`）直接对应一个 `StudioSegment`；其 `targetDurationSec` 动态计算为该场次内所有 `StudioShot.durationSec` 之和，移除 12 秒硬上限。
- **替代方案考虑**：
  - *彻底移除 `StudioSegment` 类*：会导致大量既有任务队列、数据反序列化与单测崩溃，重构风险高且无必要。
  - *保留机械等分*：无法解决音画错位与时长自相矛盾的根本问题。

### Decision 2: 真实 IP 场景卡（SceneCard）智能解析与双向映射
- **选择**：在 `convertScenesToShots` 中增加 `List<SceneCard> sceneCards` 可选参数。依据 `DramaScene.location` 和 `DramaScene.title` 进行双向子串与模糊匹配，将匹配到的真实 `scene.id`（`scene_xxx`）写入 `StudioShot.sceneId`。
- **替代方案考虑**：
  - *仅在 UI 层通过 Dropdown 手动绑定*：用户每集需要逐个镜头手动选择几十次场景，自动化拆镜体验差。

### Decision 3: 角色绰号与别名多层智能映射机制
- **选择**：在 `CharacterCard` 中新增 `aliases: List<String>` 字段（默认空列表，兼容旧 JSON），并在 `convertScenesToShots` 的出场匹配中执行多层策略：
  1. 角色全名精确包含（`c.name`）
  2. 角色配置别名匹配（`c.aliases`）
  3. 中文人名代称规则（如 3 字人名“姜七夜”智能匹配“姜七少”、“七少”、“七夜”；原著特定尊称代词匹配）。
- **替代方案考虑**：
  - *LLM 每次拆镜重新做实体对齐*：增加 Token 成本与耗时，且存在非确定性遗漏。

### Decision 4: 分镜看板全功能控制流设计（清空、重拆、单镜增删）
- **选择**：
  - 在 `StudioEpisode` 模型中新增不可变操作辅助方法：`deleteShot(int shotNumber)`、`insertShotAfter(int shotNumber)`、`clearShots()`，集中处理镜号连续平移（1..N）与片段边界重新计算。
  - 在 `StoryboardBoard` 工具栏增加「从剧本重新拆解生成」与「清空本集分镜」操作，弹出二次确认弹窗防误触。
  - 在单镜头卡片增加「删除镜头」与「在此镜后插入新镜头」交互入口。
- **替代方案考虑**：
  - *镜号保留空洞编号（如删去 #2 后只剩 #1, #3）*：会导致后续 FFmpeg 合成命令生成、剪映导出与用户直觉发生严重歧义。

### Decision 5: 时空场次批量生成向原子分镜队列调度转型
- **选择**：在 `StoryboardBoard` 与任务队列中，「一键生成整场/全集视频」不再以大段为单位提交单次 10 秒多镜混合请求，而是顺序将场内的各个分镜（`StudioShot`）作为独立原子任务加入队列；依托 `VideoGenTask` 原生首尾帧抽取与注入机制实现连续镜头的视觉强延续。
- **替代方案考虑**：
  - *保留片段单次调用并依赖 FFmpeg 切片*：因云端视频模型单次调用无法表现分镜切换逻辑，切片必然导致动作畸变与音画断裂。

## Risks / Trade-offs

- **[Risk] 旧剧集工程中存在历史 `SC001` 等抽象 sceneId**
  - → **Mitigation**: 在 `StoryboardBoard` 和 `DeliveryPanel` 中，若 `shot.sceneId` 匹配不到 `SceneCard`，尝试通过剧集的 `scenes` 场次列表反查该场次的 `location` 再次匹配 `SceneCard`；若均不匹配，安全回落为空，不抛出异常。
- **[Risk] 用户误触「一键清空」或「从剧本重新拆解」导致已出分镜与提示词丢失**
  - → **Mitigation**: 必须弹出强制二次确认对话框，明确展示警告文本；且仅在用户显式确认后持久化落盘。
- **[Risk] 单镜头删除或插入后，关联的已生成媒体文件归属错乱**
  - → **Mitigation**: 重新平移镜号时，镜头模型内部保存的 `clipPath` 与 `framePath` 包含相对唯一文件名，不随镜号重编而失效；同时清空被插入镜头的空白状态，确保状态机严密。

## Migration Plan

1. **模型与引擎升级**：在 `StudioEpisode` 增加镜头增删与场次重算方法，在 `AiConstraintEngine` 增加场景卡绑定与别名识别。
2. **UI 改造**：在 `StoryboardBoard` 工具栏与卡片中接入清空、重拆、单镜增删功能；改造整场视频生成为顺序分镜入队。
3. **合成对齐**：优化 `DeliveryPanel`，消除等分切片除法，对齐分镜独立时长。
4. **编译与本地部署**：执行 `flutter analyze`、相关单元测试，并按照规则执行 `./scripts/deploy_local.sh` 替换本机应用。
