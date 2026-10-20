## Context

动机见 proposal.md — Why；行为契约见 specs/。此处只记影响实现方式的现状与约束。

**现有目录结构**（`studio_project_manager.dart` 头部注释）：
```
AppSupportDir/video_studio/
├── global_library/bgm/*.mp3      ← 已有，跨剧 BGM
├── global_library/sfx/*.wav      ← 已有，跨剧音效
└── series_library/<series-id>/
    └── episodes/<ep-id>/
        ├── frames/  clips/  segments/  audio/  exports/
```
`global_library` 已有扫描与缓存机制（`scanGlobalLibrary`），但只处理 `bgm`/`sfx` 两类音频、返回 `GlobalAudioAsset`。本次要加图片与视频两类，扫描逻辑可参照但**不复用那个方法**——它的返回类型与缓存键都写死了音频。

**参考图链路**：`CharacterCard.referenceImages` 是 `List<String>`（文件名），读取时 `p.join(manager.characterDir(seriesId, id).path, name)`。场景卡同理。这条链路决定了资产库的接入方式（见决策 1）。

**台账现状**（`video_task_ledger.dart`）：供应商中立的任务记录，字段含 `remoteTaskId` / `status` / `lastRemoteStatus` / `lastProgress` / context / `targetPath`。当前只有视频任务会登记；图片生成是同步接口、无任务 ID，从未留痕。

**云端 URL 时效（实测）**：任务完成后 `expires_at` 为 null，十分钟前完成的任务仍可下载（HTTP 200）。因此"已完成任务永久保留 + 可重新取回"在技术上成立。

**约束**：
- 资产库初建为空，既有剧集数据零迁移。
- 不改 `CharacterCard` / `SceneCard` 的数据模型。
- 不改既有合成与导出的顺序规则。

## Goals / Non-Goals

**Goals:**
- 本地资产有稳定 ID、有来源元数据、可跨剧引用（图片→角色/场景参考图，视频→合成时间线）。
- 云端调用记录永久保留、可轻量刷新、可重新取回。
- 资产与调用记录双向可导航（资产→来源调用，调用记录→产物）。

**Non-Goals:**
- 不做标签/搜索/分类体系——初版只有来源元数据与列表。
- 不做跨设备同步。
- 不做"自动入库"——所有入库都是用户主动触发。
- 不给图片生成造任务 ID（它没有，spec 要求留空而非伪造）。

## Decisions

### 决策 1：资产库经「复制」接入参考图链路，不做跨目录引用

`referenceImages` 存文件名、从卡片自己的目录读。资产库接入方式是在角色卡/场景卡编辑界面加「从资产库选择」，选中即复制到卡片目录并加入列表。

备选 A：让 `referenceImages` 支持相对路径，直接指向资产库。否——那让剧集对资产库产生隐式依赖，用户清理资产库时剧集会以"参考图丢失"的怪病形式坏掉。本项目已有 `app_paths` 单一性回归测试在防这类事，不该新开一个入口。
备选 B：把 `referenceImages` 改成存资产 ID。否——数据模型大改 + 旧剧集迁移，而收益只是省一次复制。

代价：同一张图被 N 个角色引用就有 N 份副本。可接受——参考图通常几百 KB，且用户本就要为"这个角色用这张脸"的语义付费。

### 决策 2：资产 ID 用短随机串，文件名即 ID

`asset_index.json` 一条记录对应 `global_library/images/<id>.<ext>`。ID 用 8 位十六进制（`a3f8c1d2`），碰撞重生成。

备选：UUID。否——文件名即 ID 是要给人看的（面板里显示、日志里追），36 位 UUID 在 UI 里是噪音。
备选：语义 slug（`雨夜天台-少女回眸`）。否——中文文件名在跨平台/导出/ shell 场景下都是麻烦源，本项目其他地方一律用 id。

### 决策 3：资产索引是单 JSON 文件，不用 SQLite

条目量级：用户精选资产，预期几百条。单 JSON + 原子写（临时文件 + rename，与 `NovelChapterStorage` / `video_task_ledger` 同一套）足够。

备选：SQLite。否——引入 schema 迁移负担，而这里没有查询需求（没有标签检索）。若将来要做检索，届时再迁，数据是一整条记录、导出迁移不难。

### 决策 4：调用记录与资产索引是两个文件，不是一个

台账（`video_task_ledger/tasks.json`）记**所有**远端调用，含失败；资产索引（`asset_index.json`）记**用户精选**的本地资产。两者用 `sourceCallId` 关联：资产记它来自哪次调用。

备选：合成一个文件、用 `kind` 区分。否——两者的生命周期与清理策略根本不同（调用记录含失败、资产只含精选），混在一起会让"清理"和"永久保留"两个策略互相干扰。spec 里「已完成调用记录永久保留」与「资产是精选」是两个独立断言，正需要两个独立存储来承载。

### 决策 5：视频资产进时间线 = 合成面板多一个素材来源

`DeliveryPanel._readyClips` 按分镜顺序消费 `clips/` 与 `segments/`。资产片段作为**追加来源**接入：用户从资产库选一个片段，它按被放置的位置参与同一套顺序规则。

备选：资产片段作为"覆盖"某个分镜的产物。否——那要改顺序规则本身，而 spec 明确要求 MUST NOT 改变既有顺序规则。

注意：视频资产的"被引用"比图片窄——你不会把 4 秒片段当参考图传给模型。所以视频资产只有时间线一个引用入口，没有"作为参考图"一说。

### 决策 6：轻量刷新是一个新方法，不改轮询循环

`refreshStatusOnce(localId)` 只调一次 `_queryTask` 并更新台账，不碰 `_pollUntilDone` 的预算与 `sawInProgress` 状态。

备选：复用 `resumePolling` 但传零预算。否——那会让"刷新"和"继续等待"共享代码路径，而它们的取消语义、错误处理、UI 反馈都不同。共享的只是底层那一次 HTTP 查询（`_queryTask`），那已经复用了。

### 决策 7：无任务 ID 的图片调用，记录挂在调用台账而非任务台账

图片同步生成没有 `remoteTaskId`，但它仍是一次远端调用。台账条目照记，`remoteTaskId` 为空串。

这要求台账的 `record()` 允许空 `remoteTaskId`——当前实现里 `record` 用它做去重键（`_entries.removeWhere((e) => e.remoteTaskId == remoteTaskId)`）。空串会让所有图片调用互判重复。**必须改用 `localId` 做去重键**，`localId` 由调用方生成（图片路径 UUID）。这是本决策引出的一个必要实现改动。

## Risks / Trade-offs

- **[资产索引与台账两个文件可能不一致]** → 关联是单向的（资产 → `sourceCallId`），读取侧永远从资产出发查调用记录；调用记录不反向记"我是否被收进资产库"。少一个方向的关联就少一类不一致。
- **[复制导致磁盘占用增长]** → 入库前显示文件大小；不设自动清理。用户主动删资产即真删（文件 + 索引条目）。
- **[永久保留的调用记录无限增长]** → 每条几百字节，一年几千条数 MB，可接受。若将来成问题，加一个"归档到单独文件"的导出动作，而不是删。
- **[资产 ID 碰撞]** → 8 位十六位空间 43 亿，几百条量级下碰撞概率极低；仍做存在性检查，撞了重生成。
- **[改 `record()` 去重键会影响既有视频任务行为]** → `localId` 当前格式是 `'${adapterId}_$remoteTaskId'`，对视频任务保持不变；只给图片调用传新的 localId 生成规则。既有台账文件里的条目 localId 不变，读取兼容。

## Migration Plan

无数据迁移。新增两个文件路径（登记进 `allDirs`/`allFiles`），既有剧集与台账数据不动。

实施顺序：
1. `app_paths.dart` 加资产目录与索引文件路径。
2. `asset_library.dart`：索引读写、ID 生成、复制入库、按来源查询。
3. 台账扩展：`record()` 去重键改 `localId`、允许空 `remoteTaskId`、补记图片调用。
4. `refreshStatusOnce` 与「重新取回」。
5. UI：角色卡/场景卡的「从资产库选择」；合成面板的资产片段来源；任务面板的账本区。
6. 清理策略：已完成永久保留。

回滚：各部分可独立回滚；两个新文件留着无害（无对应代码时只是不被读的文件）。

验证要点：收进资产库后删原剧集目录，资产仍在且可用；角色卡从资产库选图后删该资产，角色参考图仍可用；重启后调用记录与资产索引都在。
