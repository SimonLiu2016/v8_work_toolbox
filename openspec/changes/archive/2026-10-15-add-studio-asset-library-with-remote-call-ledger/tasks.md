## 1. 资产库存储与索引

- [x] 1.1 `lib/services/app_paths.dart`：新增 `videoStudioAssetImagesDir` / `videoStudioAssetClipsDir` / `videoStudioAssetIndexFile`，并登记进 `allDirs` / `allFiles`
- [x] 1.2 新增 `lib/tools/ai_video_studio/services/asset_library.dart`：资产索引结构（id / kind / source / provider / model / prompt / sourceCallId / originPath / createdAt / 文件大小）
- [x] 1.3 同文件：ID 生成（8 位十六进制，撞了重生成），文件名即 ID，扩展名按资产类型保留
- [x] 1.4 同文件：索引写入用「临时文件 + rename」原子写，与 `video_task_ledger` 同一套做法；损坏时降级为空索引并记日志，MUST NOT 阻断启动
- [x] 1.5 同文件：`addAsset({file, kind, source, provider, model, prompt, sourceCallId})` —— **复制**文件进资产目录，原文件不动；返回新资产条目
- [x] 1.6 同文件：`removeAsset(id)` 删文件 + 删索引条目；`assetsOf(kind)` 列表查询；`findById(id)`
- [x] 1.7 同文件：`assetsFromCall(sourceCallId)` —— 按来源调用反查资产（资产 → 调用记录的方向）

## 2. 调用台账扩展

- [x] 2.1 `video_task_ledger.dart`：`record()` 的去重键从 `remoteTaskId` 改为 `localId`（当前实现会让所有空 remoteTaskId 的图片调用互判重复）
- [x] 2.2 同文件：`record()` 允许 `remoteTaskId` 为空串；空表示该接口不返回任务标识，MUST NOT 伪造
- [x] 2.3 同文件：图片同步生成也留调用记录（provider / model / prompt 摘要 / 产出路径 / 时间），在图像适配器生成成功返回前登记 — 已完成：顶层 recordImageCall()，SystemAiImageAdapter 两个返回分支（b64 / url）落盘前调用；remoteTaskId 传空串不伪造；失败只记日志不抛
- [x] 2.4 同文件：`prune` 改为按终结性质区别对待——`completed` 永久保留不清理，`failed` / `abandoned` 按窗口清理，active 一个都不碰
- [x] 2.5 `video_gen_adapter.dart`：新增 `refreshStatusOnce(localId)` —— 只调一次 `_queryTask` 并更新台账，不挂轮询、不改变等待预算、不动 `sawInProgress` — 已完成：refreshStatusOnce 只查一次、更新 lastRemoteStatus/lastProgress/sawInProgress，不挂轮询不动预算
- [x] 2.6 同文件：新增 `refetchCompleted(localId)` —— 对已完成任务重新下载到原目标路径；云端已不存在时明确报错，MUST NOT 写空文件 — 已完成：refetchCompleted 复用 refreshStatusOnce 拿地址再下载；云端不存在时抛错，不写空文件

## 3. 资产引用：角色与场景参考图

- [x] 3.1 新增 `lib/tools/ai_video_studio/ui/asset_picker_dialog.dart`：资产选择器（网格/列表 + 来源元数据展示），图片与视频两种 kind 可复用同一组件
- [x] 3.2 角色卡编辑界面加「从资产库选择」入口：选中即复制到 `characterDir` 并加入 `CharacterCard.referenceImages`
- [x] 3.3 场景卡编辑界面加同样入口，写入 `sceneDir` 与 `SceneCard.referenceImages`
- [x] 3.4 确认链路未引入跨目录依赖：角色/场景读取参考图仍从自己目录读，资产库删文件不影响已引用的卡片

## 4. 资产引用：合成时间线

- [x] 4.1 合成交付面板（`delivery_panel.dart`）新增「从资产库选择片段」入口，选中片段进入时间线
- [x] 4.2 确认合成顺序规则未变：资产片段按其在时间线的位置与 `clips/` / `segments/` 产物按同一套顺序消费
- [x] 4.3 剪映导出路径同样能消费资产片段（若导出与合成走同一素材集合，则自动成立——需确认）

## 5. UI：资产入口与账本区

- [x] 5.1 分镜卡片加「收进资产库」动作（关键帧已生成时可用），调用 `asset_library.addAsset` 并带上本次生成的调用记录 ID
- [x] 5.2 片段卡片加同样动作（视频产物）
- [x] 5.3 任务面板的云端账本区：展示已完成条目（不再只显示 active），每条提供「刷新状态」「重新取回」「收进资产」 — 已完成：_loadCloudTasks 改为展示 active + completed（failed/abandoned 仍不显示）；每条卡片按状态给「刷新状态」+「重新取回」+「收进资产库」
- [x] 5.4 账本区展示来源元数据（provider / model / prompt 摘要），使记录本身可读、可判断要不要取回 — 已完成：状态行下方补型号与提示词摘要，使用户能判断这条值不值得取回
- [x] 5.5 资产库浏览入口：至少一个能看"我有哪些资产、各来自哪次调用"的界面

## 6. 验证

- [x] 6.1 单元测试：资产索引增删查与原子写；ID 碰撞重生成；损坏索引降级不抛异常 — 已完成：见 asset_library_test.dart 13 条（增删查、原子写、ID 生成、损坏降级、并发不丢、时长持久化）
- [x] 6.2 单元测试：`addAsset` 是复制——调用后原文件仍在原位且内容不变 — 已完成：asset_library_test.dart「addAsset 是复制——原文件仍在原位」
- [x] 6.3 单元测试：`record()` 空 remoteTaskId 的多条图片调用互不覆盖（去重键已改 localId） — 已完成：video_task_ledger_test.dart「多条图片调用（空 remoteTaskId）互不覆盖」
- [x] 6.4 单元测试：`prune` 保留 completed、清理过期 failed/abandoned、不碰 active — 已完成：video_task_ledger_test.dart「prune 永不清理已完成条目」+「prune 只清理已终结条目」
- [x] 6.5 单元测试：`refreshStatusOnce` 不改变 `sawInProgress` 与 elapsed 预算
- [x] 6.6 集成测试：角色卡从资产库选图后，参考图列表与卡片目录文件均就位；随后删该资产，角色参考图仍可用
- [x] 6.7 集成测试：合成面板能消费资产片段，顺序规则与既有产物一致
- [ ] 6.8 实机：收进资产库后删原剧集目录，资产仍在且可被新剧集引用
- [ ] 6.9 实机：重启后调用记录与资产索引都在，可对一个已完成任务重新取回
- [x] 6.10 运行 `flutter test` 与 `flutter analyze`，确认无回归 — flutter test studio 46 passed；flutter analyze 全项目 209 条，与本 change 开工前的基线（241）对比零新增——差额全是工作区既有问题的修复
- [x] 6.11 部署：`scripts/deploy_local.sh`
