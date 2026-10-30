## 1. Data Models & Hierarchy Realignment

- [x] 1.1 在 `CharacterCard` 中增加 `aliases`（别名列表）字段与无损 JSON 序列化支持
- [x] 1.2 在 `StudioEpisode` 中实现 `deleteShot`、`insertShotAfter`、`clearShots` 以及按 `DramaScene` 1:1 构建 `StudioSegment` 的辅助方法（时长为分镜之和，无 12s 上限）

## 2. SceneCard Resolution & Character Nickname Matching

- [x] 2.1 更新 `AiConstraintEngine.convertScenesToShots` 接收 `List<SceneCard>` 并将分镜 `sceneId` 绑定至真实场景卡 ID
- [x] 2.2 强化 `AiConstraintEngine` 角色出场匹配机制，支持 `c.aliases` 及中文昵称/代称启发式匹配
- [x] 2.3 改造 `ScreenplayPanel._convertToStoryboard`，传入真实场景库并使用场次对齐的大段构建逻辑

## 3. Storyboard Board Full Lifecycle Controls

- [x] 3.1 在 `StoryboardBoard` 工具栏增加「一键清空本集分镜」功能并配置防误触确认弹窗
- [x] 3.2 在 `StoryboardBoard` 工具栏增加「从剧本重新拆解生成」功能并配置覆盖确认弹窗
- [x] 3.3 在 `_ShotCard` 中增加「删除镜头」与「在此镜后插入新镜头」交互及状态联动
- [x] 3.4 改造场次/大段批量视频生成逻辑，改为顺序触发原子分镜（StudioShot）入队与首尾帧接力

## 4. Delivery Panel & Slicing Alignment

- [x] 4.1 在 `DeliveryPanel` 中优化分镜时长与片段回退逻辑，移除片段粗暴等分除法，保持音画 1:1 对齐

## 5. Verification & Local Deployment

- [x] 5.1 运行分镜数据流、拆镜与约束引擎单元测试
- [x] 5.2 执行 `flutter analyze` 确保无代码问题
- [x] 5.3 执行 `./scripts/deploy_local.sh` 完成编译、签名并替换本机运行应用

## 6. Robust SceneCard Token Resolution, Auto-Sync & Screenplay SceneCard Binding

- [x] 6.1 在 `DramaScene` 中增加 `sceneCardId` 字段，并在剧本工作台（`ScreenplayPanel`）头部提供「关联场景库」下拉选择与联动
- [x] 6.2 升级 `AiConstraintEngine.convertScenesToShots` 的场景卡匹配引擎，采用分词打分（Token Overlap Scoring），彻底移除 `resolvedSceneId = scene.id` 的错误回退
- [x] 6.3 在 `StudioProjectManager` 中增加剧本未收录场景自动补齐入库逻辑，并在粗大纲拆镜后将分镜 `scene_id` 进行解析归一化绑定
- [x] 6.4 编写迁移/修复逻辑，修复当前项目（TTY 剧集）的历史分镜场景关联（SC001/SC002/SC003）
- [x] 6.5 编写并通过相关单元测试，执行 `flutter analyze` 确保类型与语法健全
- [x] 6.6 严格执行 `./scripts/deploy_local.sh` 完成编译、重新签名并替换本机运行应用

## 7. Strict Exclusive Segment Grouping without BeatId Bleed

- [x] 7.1 重构 `StudioEpisode.buildSegmentsFromScenes`，采用严格的 `s.segmentId == segId` 匹配并引入全局排他集合（`claimedShotNumbers`），彻底废除引起跨场次镜头重复的 `beatId` 模糊过滤
- [x] 7.2 修复当前剧集（TTY）的历史 `segments` 数据，使大段 1 为 [1,2,3]、大段 2 为 [4..10]、大段 3 为 [11..14]
- [x] 7.3 在单元测试中增加多场次共用相同节拍编号（B01..B03）时分镜无重复归组的断言
- [x] 7.4 执行 `flutter analyze` 确保类型与语法健全
- [x] 7.5 严格执行 `./scripts/deploy_local.sh` 完成编译、重新签名并替换本机运行应用



