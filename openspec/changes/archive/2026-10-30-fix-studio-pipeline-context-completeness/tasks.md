## 1. 拆镜上下文补传节拍字段

- [x] 1.1 `ai_constraint_engine.dart` 的 `scriptBreakdown5D` 扩展 `scenesBlock` 中节拍行的输出：在既有 `id` / `dramaticFunction` / `name` / `action` 之外，按需追加 `dialogue`（含说话人前缀）、`voiceType`、`subtext`、`shotSize`、`cameraStaging`、`cameraMove`、`screenPosition`、`gazeDirection`
- [x] 1.2 节拍字段为空时省略该字段，不写占位符
- [x] 1.3 单测：含台词与机位的节拍，其台词原文、说话人、景别、机位均出现在 `scriptBreakdown5D` 的 userPrompt 中
- [x] 1.4 单测：节拍未填写运镜与视线时，userPrompt 中不出现这两个字段
- [x] 1.5 全库检索确认无既有用例断言 scenesBlock 的节拍行格式（grep `节拍`/`场次规划与节拍` 于 test/ 零命中），新增用例见 1.3~1.4

## 2. 两个拆镜入口输入源统一

- [x] 2.1 抽取共享的输入取值逻辑：`synopsis = screenplayText.trim().isNotEmpty ? screenplayText.trim() : ep.synopsis.trim()`，`scenes = ep.scenes`，`contract = ep.protectedContract`
- [x] 2.2 `screenplay_panel.dart` 的 `_breakdownWithAi` 改用 2.1 的取值逻辑（保留 `_isRawTextMode` 下取控制器内容的分支）
- [x] 2.3 `storyboard_board.dart` 的 `_breakdown` 改用 2.1 的取值逻辑，不再以 `_synopsisController.text` 作为唯一剧情来源
- [x] 2.4 单测：同一集分别从两处入口触发拆镜，提交给 AI 的剧情上下文一致

## 3. 剧本生成注入资产上下文

- [x] 3.1 `ai_constraint_engine.dart` 的 `screenplayGeneration` 新增三个可选参数：`characterProfiles`（`List<String>`）、`sceneNames`（`List<String>`）、`protectedContract`
- [x] 3.2 在引擎内按既定规则格式化角色设定文本（姓名 + `facialFeaturesZh` + `defaultAttireZh`，缺失字段省略）并注入 userPrompt
- [x] 3.3 `screenplay_panel.dart` 的 `_generateScreenplayWithAi` 从 `_characters` / `_sceneCards` / `ep.protectedContract` 构造上述三个参数传入
- [x] 3.4 单测：传入角色设定、场景卡名与契约后，三者均出现在 `screenplayGeneration` 的 userPrompt 中
- [x] 3.5 单测：不传三个新参数时（默认空值），行为与当前一致

## 4. 形态解析优先级下沉为共享函数

- [x] 4.1 将 `storyboard_board.dart` 的 `_resolveVariation` 三级优先级（shot → episode override → active）下沉为共享静态函数（建议置于 `StudioProjectManager` 或新建工具类）
- [x] 4.2 `storyboard_board.dart` 的 `_resolveVariation` 改为调用 4.1 的共享函数，行为不变
- [x] 4.3 单测：三级优先级的每一种组合都返回预期形态（shot 指定优先、episode 覆盖次之、默认 active 兜底、三级都无返回 null）

## 5. 生图参考图取材与生视频同源

- [x] 5.1 `studio_generation_tasks.dart` 的 `ImageGenTask.run` 用 4.1 的共享函数为每个出场角色解析形态，构造临时角色卡（`activeVariation` 换为解析结果）
- [x] 5.2 `ImageGenTask` 改用 `AssetBindingResolver.resolve` 收集参考图，替换自写的 `_referenceImages` 挑选逻辑；场景参考图仍走 resolver 的场景分支
- [x] 5.3 删除 `ImageGenTask._referenceImages` 中与 resolver 重复的挑选代码，保留其返回类型供 5.4 使用
- [x] 5.4 单测：同一分镜在 `ImageGenTask` 与 `VideoGenTask` 两条路径下得到相同的有序参考图文件列表
- [x] 5.5 单测：用户在分镜卡为角色指定了上传参考图时，`ImageGenTask` 使用该指定图而非基准三视图
- [x] 5.6 更新 `test/ai_video_studio_generation_task_test.dart` 中依赖旧取材逻辑的既有断言

## 6. 生图多图编号按实际参考图顺序

- [x] 6.1 `prompt_assembler.dart` 的 `buildAgnesMultiImageDirective` 新增 `List<CharacterCard> charactersWithImages`（按参考图顺序）与 `bool hasSceneImage` 入参，编号由 `charactersWithImages` 的下标推出，`hasSceneImage` 由调用方按实际是否有场景参考图传入
- [x] 6.2 `buildShotPrompt` 的 `PromptParts` 新增承接 6.1 的字段（或由调用方传入实际参考图列表后在内部推导）
- [x] 6.3 `studio_generation_tasks.dart` 的 `ImageGenTask.run` 按 5.2 得到的实际参考图列表构造 6.2 的入参，`isMultiImage` 与 `hasCharacterReferences` 改按列表长度计算
- [x] 6.4 `storyboard_board.dart` 的 `_reassemblePrompt` 同步按同一规则构造（避免 UI 预览与实际生成不一致）
- [x] 6.5 单测：角色甲无素材、角色乙有三视图时，提示词声明「第 1 张图作为角色乙」，MUST NOT 声明「第 1 张图作为角色甲」
- [x] 6.6 更新 `test/ai_video_studio_prompt_assembler_test.dart:839` 附近依赖旧编号规则的断言

## 7. videoPrompt 缓存失效

- [x] 7.1 `studio_models.dart` 的 `StudioShot` 新增 `videoPromptSourceKey`（字符串）字段，完成 `toJson` / `fromJson` / `copyWith`；反序列化缺失时为空串
- [x] 7.2 定义稳定的来源键构造函数：按 key 排序拼接 `actionZh` / `dialogue` / 排序后 `characterIds` / `sceneId` / 按 key 排序后的 `assetBindings` 序列化
- [x] 7.3 写入 `videoPrompt` 的位置（视频提示词对话框保存、AI 重写保存）同步写入当时的来源键
- [x] 7.4 `VideoGenTask.run` 与 `buildVideoGenPrompt` 判定：当前来源键与记录键不一致时，视为失效，走动态组装（不删除 `videoPrompt` 字段）
- [x] 7.5 `storyboard_board.dart` 分镜卡在检测到失效时显示提示「字段已变更，视频提示词已回退自动组装」
- [x] 7.6 单测：仅修改时长/画幅/分辨率时来源键不变，定制 `videoPrompt` 仍然生效
- [x] 7.7 单测：修改动作/台词/出场角色/场景/素材绑定任一字段后，定制 `videoPrompt` 被忽略，生成用动态组装且含最新 `<Picture N>` 指代
- [x] 7.8 单测：`assetBindings` 的 Map 顺序变化不影响来源键（序列化按 key 排序）

## 8. 任务队列依赖（先图后视频）

- [x] 8.1 **前置确认**：确认数据诚实性变更的 tasks 3.5（接力判据）已完成；若未完成，先完成它再动本组——否则接力仍会静默覆盖首帧，本组的正确提示词会配错的首帧
- [x] 8.2 `studio_task_queue.dart` 的 `StudioTask` 新增 `requiresTaskId: String?`，`enqueue` 增加对应可选参数
- [x] 8.3 `_drain` 选取下一个可启动任务时，跳过 `requiresTaskId` 指向的任务仍处于非终态、或终态为 failed/cancelled 的候选项
- [x] 8.4 被依赖任务失败/取消时，将等待方标记为 failed，错误信息为「前置任务未满足」并附前置任务 id
- [x] 8.5 队列面板把「等待前置」状态显示出来（区别于「等待中」），避免用户以为卡住
- [x] 8.6 `storyboard_board.dart` 的 `_enqueueSegment` 与 `_enqueueAllSegments`：`await _enqueueFrame(shot)` 后拿到返回的任务 id，将其作为 `_enqueueClip(shot)` 入队时的 `requiresTaskId`
- [x] 8.7 `_enqueueClip` 增加可选参数 `requiresTaskId` 并透传给 `_queue.enqueue`
- [x] 8.8 单测：无关键帧时分镜的视频任务等待同镜生图任务，不提前启动
- [x] 8.9 单测：生图任务失败时，等待它的视频任务被标记为前置未满足，不启动
- [x] 8.10 单测：关键帧已就绪时直接入队视频任务，不建立依赖也不重复入队生图任务
- [x] 8.11 全文件 22 项既有用例（并发上限/状态跟踪/取消/片段任务）在依赖改动后全部通过，无需修改；新增 4 项依赖用例见 8.8~8.10

## 9. 回归与验证

- [x] 9.1 studio 域 417 通过 / 3 失败。3 项全部为改动前既有红：`asset_library_page_test.dart` 的 3 个
      widget 测试（已用 `git stash` 回退 lib/ 后复跑确认同样失败，与本次改动无关）。
- [x] 9.2 `flutter analyze lib/` 0 error。ai_video_studio 子树 8 issue（基线 18，减少 10 个），
      全部为 info 级且不含我改动的文件。
- [x] 9.3 已通过
- [ ] 9.4 端到端手测：剧本工作台写台词与机位 → 拆镜 → 确认台词与机位进入分镜；分镜卡绑定素材 → 生图 → 确认用的是绑定的图；改动作字段 → 确认视频提示词回退自动组装
      （需真实 AI Key 与 GUI，留给使用方验收；自动化覆盖见 1.3/5.5/7.7）
