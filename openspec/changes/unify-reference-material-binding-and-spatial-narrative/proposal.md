## Why

分镜看板生成的视频有三类系统性缺陷，全部源于「视频提示词没有把分镜的结构化信息讲清楚」：

1. **人物长相对不上 IP 主库**。reference 模式下 `images[]` 传了 N 张图，但提示词里没有任何地方声明「第 N 张图是谁」。模型只能猜，猜错就把参考图当成氛围参考，自行臆造人物长相。分镜级提示词完全没有 `<Picture N>`；片段级有但只写在顶部身份锚点段，12 秒的动作序列里提到角色时是裸名字，编号已在注意力范围外。
2. **两个角色各自对着镜头，不对着对方**。`screenPosition`（画内左右）与 `gazeDirection`（视线方向向量）进了视频提示词，但 `gazeTarget`（目光聚焦于谁）从未进入——它目前只被生图路径消费。模型不知道「姜七夜看着老王、老王看着姜七夜」，中立站姿的默认视线就是镜头。
3. **多角色镜头在 UI 上无法表达**。分镜卡的角色选择器是单选，赋值写死 `characterIds: [val]`，选第二个角色会覆盖第一个。数据模型 `characterIds` 是 `List<String>` 且有消费多角色的代码，但生产入口只有一个单选下拉。同时没有任何界面能让用户声明「这一镜用哪个资产文件」——程序内部两条路径各自猜（生图路径认 `turnaround.png`，视频路径硬取 `referenceImages.first`）。

此外，`<Picture N>` 要真正可用，前置条件是「分镜能声明用哪些素材、每张素材是谁」——否则编号该指向哪个文件仍然是程序在猜。

## What Changes

- **分镜卡新增「出场资产」面板**：角色多选（替代现单选下拉），每个角色可指定「主体/对峙/配角」分工与所用的素材图；场景可指定所用素材图。素材下拉列出该资产下的候选文件（三视图、面部锚点、上传参考图 / 场景七方位视角图、上传参考图）。
- **新增分镜级素材绑定字段**：分镜记录「哪个资产用哪张图、承担什么分工」。该字段是 `<Picture N>` 编号的唯一来源，替代现在两条路径各自的隐式挑选逻辑。
- **素材指代编译**：分镜级与片段级共用同一套 `<Picture N>` 编号生成，编号 SHALL 在动作行与台词行里复现，而非只写在顶部身份锚点段。
- **空间关系编译**：视频提示词新增【空间关系】段，把 `screenPosition` + `gazeDirection` + `gazeTarget` 与角色分工编译为「谁立于何处、面朝哪个方向、目光聚焦于谁、与谁对峙」。
- **时间流水提升为主结构**：现有【因果时间轴】扩展为带素材编号的连续时间流水（`0.0s-2.3s 姜七夜拱手一拜（<Picture 1>）`），片段级把 N 个分镜的同结构串成一条覆盖片段目标时长的流水。
- **参考图上限改为读能力声明**：`maxReferenceImages` 取代适配器内硬编码的 `5`。超出上限时系统 SHALL 阻止提交并提示用户减少资产，而非静默截断（静默截断会让用户以为约束已生效）。
- **清空本集分镜时归档物理媒体**：接上已有的 `archiveEpisodeMedia`（当前无任何调用方），并补上 `audio/` 目录（当前归档漏掉它）。`exports/` 保持原样不归档——成片是交付物且文件名固定会被覆盖，不产生幽灵媒体。
- **`<Audio N>` 契约**：`VideoGenRequest` 增加音频参考字段与编号体系，adapter 在 reference 模式支持 `audios` 数组。默认不传、UI 不暴露，等配音流水线前移后再启用。
- **BREAKING**：`StudioShot` 新增素材绑定字段，`storyboard.json` 结构变化。旧分镜不做自动迁移——用户将清空重测。

## Capabilities

### New Capabilities

- `ai-video-studio/shot-asset-binding`: 定义分镜如何声明「出场哪些资产、各用哪张素材图、承担什么分工」，以及该声明如何成为素材指代编号的唯一来源。

### Modified Capabilities

- `ai-video-studio/shot-production`: 分镜级视频提示词的构成要求变化——新增【空间关系】段、素材指代编号在动作/台词行复现、时间轴带编号；「清空本集分镜」的语义扩展为同时归档物理媒体。
- `ai-video-studio/segment-production`: 「片段提示词组装」要求变化——片段提示词的动作/台词序列 SHALL 带素材指代编号，且编号与参考图数组严格同序；片段级覆盖多分镜时 SHALL 输出一条连续时间流水。
- `ai-video-studio/shot-continuity`: 「台账注入生成提示词」要求扩展——`gazeTarget` 与 `screenPosition` 须编译为角色间的相对空间关系，而非仅方向向量。
- `ai-video-studio/storyboard-visual-composition`: 「Agnes video generation payload contract」要求变化——参考图数量上限 SHALL 来自模型能力声明，超出时阻止提交而非静默截断；reference 模式的媒体数组 SHALL 支持音频参考及其编号。

## Impact

**代码**
- `lib/tools/ai_video_studio/models/studio_models.dart` — `StudioShot` 新增素材绑定字段与序列化；角色分工枚举。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart` — 角色单选下拉改为「出场资产」面板（多角色 + 分工 + 素材下拉 + 超限提示）；清空流程接上媒体归档。
- `lib/tools/ai_video_studio/services/prompt_assembler.dart` — 新增素材指代编译与【空间关系】段；`buildVideoGenPrompt` / `buildSegmentPrompt` 的动作台词行复现编号；时间轴带编号。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` — 两条路径统一读素材绑定，替换各自隐式挑选参考图的逻辑。
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart` — 硬编码 `5` 改为读 `capability.maxReferenceImages`，超限报错而非 `take(5)`；`VideoGenRequest` 增加音频参考字段；reference 模式 payload 支持 `audios`。
- `lib/services/media_capability.dart` — Agnes 视频型号的 `maxReferenceImages` 按实际能力声明。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart` — `archiveEpisodeMedia` 补 `audio/` 目录。
- `lib/tools/ai_video_studio/ui/settings_dialog.dart` / `studio_settings_dialog.dart` — 参考图上限可配置（若采用设置项而非仅能力声明）。

**风险**
- 分镜卡面板改动大，与现有景别/运镜/模式/画幅等控件争夺空间。
- 两条生成路径统一后，片段级生成的参考图集合可能变化（从「全部出场角色的第一张图」变为「用户绑定的素材」），已生成片段重跑时画面会变。
- 静默截断改为报错后，历史上能跑通的多资产分镜会被阻止，需要用户手动减资产。
