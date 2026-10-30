## 1. 分镜素材绑定数据模型

- [x] 1.1 `studio_models.dart` 新增 `ShotAssetRole` 枚举（`subject` 主体 / `confrontation` 对峙 / `supporting` 配角）与 `ShotAssetBinding` 值对象（`materialPath`、`role`）
- [x] 1.2 `StudioShot` 新增 `assetBindings: Map<String, ShotAssetBinding>`（key 为角色卡 id 或场景卡 id），完成 `toJson` / `fromJson` / `copyWith`
- [x] 1.3 新增资产候选图枚举工具：输入角色卡或场景卡，返回该资产下可用于生成的候选素材文件列表（角色：形态三视图 → `turnaround.png` → `turnaround_chibi.png` → `face_anchor.png` → `referenceImages`；场景：七方位视角图 → `referenceImages`），并标记哪个是系统默认
- [x] 1.4 为 1.3 编写单测：候选列表包含全部可用素材且默认项与生图路径 `_referenceImages` 的选取结果一致
- [x] 1.5 为 1.2 编写单测：`assetBindings` 序列化往返后字段不丢；缺失该字段的旧 JSON 解析为空绑定而非抛异常

## 2. 分镜卡「出场资产」面板（E）

- [x] 2.1 将现有「角色」单选下拉与「形态」下拉从卡片主区域移出，改为折叠式「出场资产」面板（默认收起）
- [x] 2.2 面板内角色区支持多角色：可添加、可移除，后添加的角色不覆盖先添加的；每个角色一行，含分工下拉（主体/对峙/配角）与素材下拉
- [x] 2.3 素材下拉列出该角色的全部候选素材（复用 1.3），默认选中系统默认项，用户可改；未显式指定时 UI 展示「自动：<默认文件名>」
- [x] 2.4 面板内场景区支持指定场景素材图（候选来自 1.3 的场景分支）；「场景」主行保留为选择关联哪个场景卡
- [x] 2.5 超限提示：当绑定素材总数超过当前视频模型声明的参考图上限时，面板内显示警告条，说明当前上限与已选数量，并提供「了解」入口
- [x] 2.6 编写 widget 测试：双人镜头可添加两个角色且互不覆盖；素材下拉可改选；超限时警告条出现

## 3. 素材指代编号与取材统一（A）

- [x] 3.1 新增共享取材函数：输入分镜的 `assetBindings` 与角色/场景卡，返回**有序的**素材绑定列表（`{assetId, assetName, role, filePath}`）；空 `materialPath` 时按 1.3 的默认规则取
- [x] 3.2 编号规则：有序列表下标 + 1 即 `<Picture N>`，提示词编译与提交数组从同一列表产出，移除依赖名称匹配的 `indexWhere`
- [x] 3.3 `VideoGenTask`（分镜级）改用 3.1 的取材函数，删除自写的 `referenceImages.first` / `faceAnchorPath` 逻辑
- [x] 3.4 `SegmentVideoGenTask`（片段级）改用 3.1 的取材函数，删除自写的取材逻辑
- [x] 3.5 `buildSegmentPrompt` 的 `references` 参数改为接收 3.1 的有序列表，编号直接由下标得出；`{{ref N}}` 写法统一为 `<Picture N>`
- [x] 3.6 为 3.1 编写单测：同一分镜在分镜级与片段级取材得到相同的有序列表
- [x] 3.7 为 3.2 编写单测：编号与列表下标严格对应，无名称匹配环节

## 4. 素材指代进入提示词行（A）

- [x] 4.1 `buildVideoGenPrompt` 新增【素材指代】段，逐行声明「`<Picture N>` = 资产名（角色/场景，分工）」
- [x] 4.2 `buildVideoGenPrompt` 的出场人物段：已绑定素材的角色 SHALL NOT 重复书写静态外貌长文，仅写名称、分工与空间关系
- [x] 4.3 【因果时间轴】的每一行带上该行主体对应的 `<Picture N>`；主体从动作/台词文本中按角色名匹配得出
- [x] 4.4 `buildSegmentPrompt` 的动作行与台词行带上 `<Picture N>`，编号不只出现在顶部锚点段
- [x] 4.5 为 4.1~4.4 编写单测：双人镜的提示词中，老王的动作行与台词行均含 `<Picture 2>`；姜七夜的行含 `<Picture 1>`；顶部锚点段同样含编号
- [x] 4.6 为 4.2 编写单测：已绑定素材的角色，其 `descriptionZh` 长文不出现在视频提示词中

## 5. 空间关系编译（B）

- [x] 5.1 `buildVideoGenPrompt` 新增【空间关系】段，输入为 `assetBindings` 的分工、`continuity.screenPosition`、`gazeDirection`、`gazeTarget`
- [x] 5.2 编译规则：写出每个角色的所立位置与面朝方向；`gazeTarget` 非空时写「目光聚焦于X」；两个及以上角色且存在 `confrontation` 分工时，明确写出相互注视与相对朝向
- [x] 5.3 单角色镜不编译他人注视关系；`gazeTarget` 为空时不编造注视对象
- [x] 5.4 片段级提示词同步注入空间关系段（取该片段首个分镜或主场景的台账）
- [x] 5.5 为 5.2 编写单测：姜七夜（主体）与老王（对峙）同镜时，输出含「姜七夜目光聚焦于老王」与「老王目光聚焦于姜七夜」
- [x] 5.6 为 5.3 编写单测：单角色镜不含任何「聚焦于某角色」表述；`gazeTarget` 为空时不出现注视描述

## 6. 片段级连续时间流水（C）

- [x] 6.1 复用 `CausalityTimelineCompiler.cumulativeRanges`，片段内各分镜区间首镜从 0.0 起算、后续紧接前镜结束时刻，末镜结束 = 片段目标时长
- [x] 6.2 为 6.1 编写单测：4.0/3.0/5.0 秒三分镜产出 0.0-4.0、4.0-7.0、7.0-12.0，区间首尾相接

## 7. 参考图上限可配置（替换硬编码 5）

- [x] 7.1 `AgnesVideoAdapter` 删除 `refUris.length > 5` 的硬编码截断，改为读 `capability.maxReferenceImages`
- [x] 7.2 超出上限时抛 `StateError`，错误信息含声明上限与实际提交数量，SHALL NOT 静默 `take(n)`
- [x] 7.3 `media_capability.dart` 按型号填写 `maxReferenceImages`：`agnes-video-2.5` 为 8、`agnes-video-2.5-flash` 为 5；两者各自声明，不冲突
- [x] 7.4 参考图上限在界面可改（设置项），供应商调整上限时用户可自行修正，不必等发版；改动后即时作用于分镜卡的警告条与 adapter 的校验
- [x] 7.5 为 7.1~7.2 编写单测：传入超出上限的参考图数量时适配器抛错且错误信息含上限值；未超限时正常提交
- [x] 7.6 为 7.4 编写单测：修改设置的上限值后，adapter 与分镜卡警告条读到的都是新值
- [x] 7.7 全量 `flutter test`，确认原依赖静默截断行为的既有断言已更新

## 8. `<Audio N>` 契约（D，不暴露 UI）

- [x] 8.1 `VideoGenRequest` 新增 `audioReferences: List<File>` 字段与访问器，默认空列表
- [x] 8.2 `AgnesVideoAdapter` 在 reference 模式下支持将音频参考放入参考媒体数组；未提供音频时不提交任何音频字段
- [x] 8.3 提示词编译支持 `<Audio N>` 编号，编号与提交的音频参考数组同序
- [x] 8.4 为 8.2~8.3 编写单测：未提供音频时 payload 无音频字段且提示词无音频编号；提供一段音频时编号与数组位置一致
- [x] 8.5 确认 UI 无音频素材入口，两条生成路径均不传 `audioReferences`

## 9. 清空本集分镜时归档物理媒体（F）

- [x] 9.1 `archiveEpisodeMedia` 的 `subDirs` 增加 `episodeAudioDir`（当前遗漏）
- [x] 9.2 `_confirmAndClearAllShots` 在 `saveEpisode` 之后调用 `archiveEpisodeMedia`，失败不阻断清空主流程但需告知用户
- [x] 9.3 `exports/` 不纳入归档范围（成片为交付物且文件名固定）
- [x] 9.4 弹窗文案更新：明示媒体将被归档（而非「保留在原位」），并告知归档目录形如 `archive/archived_<时间戳>/`
- [x] 9.5 清空成功后的 SnackBar 告知归档文件数与可定位位置
- [x] 9.6 编写单测：清空后 `clips/`、`frames/`、`segments/`、`audio/` 中的文件均不在原目录、已存在于归档目录；`exports/` 文件保持原位

## 10. 回归与验证

- [x] 10.1 更新 `test/ai_video_studio_prompt_assembler_test.dart` 中受 `<Picture N>` 与 `{{ref N}}` 统一影响的断言
- [x] 10.2 更新 `test/ai_video_studio_adapter_test.dart` 中依赖静默截断的断言
- [x] 10.3 跑 `test/ai_video_studio_prompt_assembler_test.dart`、`test/tools/ai_video_studio/shot_causality_ordering_test.dart`、`test/tools/ai_video_studio/director_validation_causality_test.dart`、`test/ai_video_studio_ffmpeg_test.dart`、`test/agnes_studio_pipeline_test.dart`，确认无回归
- [x] 10.4 全量 `flutter test`，确认无新增失败
- [x] 10.5 `flutter analyze lib/` 确认 0 error
- [x] 10.6 归档前 `openspec validate unify-reference-material-binding-and-spatial-narrative --strict` 通过
