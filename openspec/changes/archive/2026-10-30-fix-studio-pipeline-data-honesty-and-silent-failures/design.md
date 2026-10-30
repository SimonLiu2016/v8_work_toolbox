## Context

流水线当前的破坏性行为分散在四个互不相干的模块里，但共用一个根因：**写入方从不校验自己是否有权改写目标数据**。导入服务把"未执行"写成 `success`，看板把"读取输入"写成"回写字段"，接力把"前一镜的产物"当成本镜的首帧，本地映射把"未推导"写成"常量占位"。

本设计只处理这四个写入点的判据修正，不重构它们所在的数据流。动机见 proposal.md — Why。

约束：`storyboard.json` 是唯一事实源，所有修正必须在字段级合并（`StudioProjectManager.updateShot`）的既有语义内完成，不引入新的并发写路径。

## Goals / Non-Goals

**Goals:**
- 让每一个被写入的字段都能回答"这个值是从哪来的"。
- 让"未执行"与"已成功"在数据层可区分，而不是只在 UI 文案上区分。
- 让本地映射产出的分镜与 AI 拆镜产出的分镜在质检引擎眼中没有差别待遇。

**Non-Goals:**
- 不重构 `scenes` / `screenplayText` / `synopsis` 三者的单一事实源关系（需要产品决策，另行立项）。
- 不引入 markdown → `DramaScene` 反向解析。
- 不改任务队列的依赖控制（由配套变更跟踪）。
- 不改 `scriptBreakdown5D` 的提示词内容。

## Decisions

### Decision 1: 阶段状态机新增 `skipped` 终态，而非复用 `pending`

`StageStatus` 增加 `skipped`。`advancePipelineStage` 的回填逻辑（把先前阶段一并标 success）**必须跳过 `skipped` 状态**，否则一次全季导入末尾的 `_finish` 会把前面所有 `skipped` 又刷成 `success`。

替代方案：复用 `pending`。否决——`pending` 的语义是"还没轮到"，终态任务里出现 `pending` 会让 UI 的任务卡片永远显示未完成。

替代方案：不加状态，只在 UI 层根据 `isFullSeason` 判断显示什么。否决——那等于把"这次到底跑没跑"的真相留在 UI 里，任何其他消费方（ledger、测试、未来的导出）都会重新踩坑。

### Decision 2: 质检通过率改为可空，空分镜时不产出数值

`NovelImportTask.auditPassRate` 由 `double`（默认 1.0）改为 `double?`。单章导入在 `currentEp.shots.isEmpty` 时置 `null` 并写入日志"无可检对象"。

默认值 1.0 是当前假 100% 的直接来源——它让"从没赋过值"和"确实是满分"共用同一个表示。改为可空后，UI 的 `if (task.auditPassRate > 0)` 判空链自然不再显示。

替代方案：保留 `double`，用 `-1` 或 `0` 表示无数据。否决——`0` 会被读成"质检全挂"，`-1` 是魔法数，两处都要特殊分支。

### Decision 3: 全季导入的删除前确认放在数据层返回清单，UI 负责呈现

`StudioProjectManager.importNovelProject` 保持"删除后重建"的既有行为，但**在此之前**新增 `previewFullSeasonImportImpact(seriesId)`，返回 `{episodeCount, shotCount, mediaFileCount}`。UI 在拿到清单后弹确认，用户确认才调 `importNovelProject`。

替代方案：把确认逻辑写进数据层（弹窗由 service 触发）。否决——service 不该依赖 BuildContext，且该服务当前是进程级单例，与 UI 生命周期解耦是它存在的全部理由（见 `novel_import_task_service.dart` 类注释）。

替代方案：软删除/归档而非真删除。否决——超出本变更范围，且归档后的媒体仍占磁盘，用户没有"我要推倒重来"的语义。

### Decision 4: 接力判据用四条件合取，全部可从一个分镜的既有字段算出

```
可接力 ⟺ prevShot.sceneId == shot.sceneId
        ∧ setEquals(prevShot.characterIds, shot.characterIds)
        ∧ ¬isReverseShot(prevShot, shot)
        ∧ abs(shotSizeRank(prevShot.shotSize) - shotSizeRank(shot.shotSize)) <= 1
```

`isReverseShot` 的判定：任一方在 `assetBindings` 中被标记为 `confrontation` 分工，或两镜中一方为特写（`close_up`）另一方非特写。前者是用户显式声明的正反打意图，后者是正反打最普遍的景别特征。

主体集合用 `characterIds` 判等而非交集非空——"上镜三个人、这镜一个人"同样是切主体，接力会穿帮。

替代方案：加一个 `continuity.dynamicExitState.unfinishedPhase` 非空的附加条件（"上一镜动作真的没做完"才接力）。否决——`convertScenesToShots` 与多数 AI 输出都不填这个字段，加上它等于默认关闭接力，与 spec 中"同场景同主体连续动作应接力"的要求冲突。

替代方案：让用户在分镜卡上手控"是否接力"。暂不做——见 Open Questions。

### Decision 5: 首帧来源用独立字段记录，不改 `firstFramePath` 的既有含义

`firstFramePath` 的既有注释已声明它记录"本镜生成视频使用的首帧"——这正是它应该有的含义，当前 bug 是写回时用了错误的变量。修正即：`inputImageFile` 是接力尾帧时，`firstFramePath` 仍写**实际使用**的那个尾帧（这符合既有语义），同时新增 `firstFrameSource`（枚举 `keyframe` / `relay` / `none`）记录来源。

不把 `firstFramePath` 拆成"本镜关键帧"与"实际首帧"两个字段——那会让所有既有消费方（playground 快照、UI 徽章）都要改，而它们想知道的都是"实际用了哪张图"。

### Decision 6: 本地映射的占位字段直接改空，不尝试推导

`convertScenesToShots` 里三个常量字段改为空串。不从 beat 推导 `temporalEvolution` ——节拍没有携带相位信息，推导等于编造，而编造的相位会让 C11 检查永久失效（这正是要修的问题）。

`holdingLeft` / `holdingRight` 保持空（当前已是空串，无需改动），但把 `worldPosition` / `lightingState` 里同样是常量的部分也改空或改为从 scene 字段推导（当前已从 `scene.timeOfDay` 推导，可保留）。

### Decision 7: 文本模式差异检测用字符串比对，不做结构化 diff

`screenplay_panel` 切换视图时比对 `_textEditorController.text` 与 `_exportToMarkdown(_scenes)`。不一致即弹确认，用户选择"保留文本修改"则停留在文本模式（或把文本写回 `screenplayText` 但不触碰 `scenes`），选择"丢弃文本修改"才覆盖控制器内容。

替代方案：自动反向解析。否决——本变更明确不做，且反向解析会引入"猜用户想改哪一场次"的不可验证行为。

## Risks / Trade-offs

- **[`skipped` 状态影响 ledger 与历史记录的呈现]** → `advancePipelineStage` 的回填逻辑显式跳过 `skipped`；既有历史记录中已是 `success` 的阶段不回改（数据迁移不做，只保证新产生的记录正确）。
- **[`auditPassRate` 改可空影响两处 UI 判断]** → `idea_incubator_panel.dart` 两处 `if (task.auditPassRate > 0)` 改为可空判断；无其他消费方（已全库确认）。
- **[接力判据收紧后，原本"能接力"的连续动作镜可能不再接力，画面连续性下降]** → 判据四条件都取自用户/AI 已声明的字段，不引入新输入；对确需接力而判据不满足的场景，见 Open Questions。
- **[全季导入确认弹窗增加一次交互，打断既有工作流]** → 仅在检测到待删数据非空时弹出；首次导入（无既有剧集）不弹。
- **[本地映射字段改空后，依赖这些字段非空的既有测试断言会失败]** → tasks 中显式列出需更新的测试文件。
- **[文本模式差异提示可能在用户无意编辑（如误触键盘）时频繁弹出]** → 提示是一次性确认对话框，不是每次切换都拦；用户选择"保留"后本次会话内该差异不再重复提示。

## Migration Plan

无需数据迁移。所有改动都是写入判据的变化，旧 `storyboard.json` 与旧任务记录照常读取：

- 旧的 `auditPassRate` 数值字段反序列化为可空类型时，非空值保留、缺失值视为 `null`。
- 新增的 `firstFrameSource` 字段缺失时视为 `keyframe`（旧数据里 `firstFramePath` 与本镜关键帧一致的常见情形）。
- `StageStatus` 新增枚举值不影响既有 JSON（阶段状态本就不持久化，仅存于任务对象）。

回滚策略：各修正点相互独立，可单独回退；无 schema 层面的不兼容变更。

## Open Questions

- **接力是否需要用户级手控开关？** 四条件合取仍可能误判（例如同主体同景别但实际是两次独立拍摄）。本变更按 spec 要求实现自动判据；若实测仍穿帮，再在分镜卡加"跨镜接力"显式开关。该开关会新增一个 `StudioShot` 字段，属于 schema 变化，需单独立项。
- **`_breakdown` 不回写 synopsis 后，分镜看板的粗大纲文本框与剧集 synopsis 的关系是否需要重新定义？** 当前文本框只是 `_synopsisController`（初始化为 `episode.synopsis` 的内存副本），不回写后它成为纯输入缓冲。这可能让用户困惑"我改的大纲存到哪了"——需要在 UI 上加一句说明，但具体文案待实现时定。
