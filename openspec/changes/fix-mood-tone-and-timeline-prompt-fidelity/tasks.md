## 1. 语气从台词解析（替换 mood 顶替）

- [x] 1.1 `prompt_assembler.dart` 新增 `extractDialogueTone(String dialogue)`：剥离预估注记后取首个括号内容，过滤含「秒/预估」的注记，长度 ≤ 12 字；解析不到返回空串
- [x] 1.2 为 1.1 编写单测：「（压低声音，咬牙）你找死！（预估2秒）」→「压低声音，咬牙」；「你站住！（预估1.5秒）」→ 空串；「（起身）」类纯动作提示 → 空串
- [x] 1.3 `buildVideoGenPrompt` 的 `toneHint` 改为取 `extractDialogueTone(dialogue)`，不再取 `ShotMood.fromId(shot.mood).label`
- [x] 1.4 语气为空时 prompt 中省略「语气：」字段，不留默认值
- [x] 1.5 为 1.3~1.4 编写单测：mood=warm + 台词「你！你站住！反了你了！」→ prompt 不含「温馨」也不含「语气：」；台词含语气提示 → prompt 含该语气

## 2. 时间轴去掉相位说明噪声

- [x] 2.1 `buildShotCausalityTimeline` 中 `temporal` 仅在 `phaseSplit != null` 时附加相位说明；解析不出时返回纯时间轴，不写「相位说明」与原文
- [x] 2.2 为 2.1 编写单测：`temporalEvolution` 为「动作处于启动及推进相位」→ prompt 不含「相位说明」且不含该原文；为「前2.0秒拱手，后3.0秒转身」→ 时间轴在 2.0 秒切分

## 3. `<Picture N>` 改为行内前置

- [x] 3.1 `buildShotCausalityTimeline` 的动作行：编号从时间段末尾移到主体名之后（`姜七夜（<Picture 1>）拱手一拜`）
- [x] 3.2 同镜多主体的动作行，按文本中出现次序为每个角色名后插入各自编号
- [x] 3.3 `buildSegmentPrompt` 的动作行与台词行同样改为行内前置
- [x] 3.4 为 3.1~3.3 编写单测：时间轴动作行含「姜七夜（<Picture 1>）」且时间段末尾无编号；片段级动作行同样

## 4. 场景参考图显式声明用途

- [x] 4.1 【素材指代】段中场景行的标注追加「仅场景环境参考，不作为人物人脸参考」
- [x] 4.2 为 4.1 编写单测：含场景素材的提示词中，场景指代行含「仅场景环境参考」

## 5. 分镜卡情绪下拉

- [x] 5.1 `_ShotCard` 控件行新增「情绪」下拉，取值 `ShotMood.values` 全部七项，onChanged 走 `shot.copyWith(mood: id)`
- [x] 5.2 下拉旁加提示：情绪同时影响画面光线与配乐推荐（mood 驱动 `MoodTokens` 与 `BgmMatcher`）
- [x] 5.3 编写 widget 测试：打开情绪下拉可见七项；改选后 `shot.mood` 更新

## 6. 时间演变为可编辑

- [x] 6.1 `_DirectorDecisionsPanel` 新增可编辑行构造器（label + 初始值 + onChanged），`TextField` 多行、带 placeholder「例：前2.0秒拱手，后3.0秒转身」
- [x] 6.2 「时间演变」行改用 6.1 的可编辑构造器，onChanged 走 `shot.copyWith(directorDecisions: d.copyWith(temporalEvolution: v))`
- [x] 6.3 其余五维字段保持只读（光影/机位已由运镜面板覆盖，美学质感是 AI 内部推导）
- [x] 6.4 编写测试：修改时间演变为可解析秒数 → 重新生成的 prompt 时间轴按该秒数切分；改为不可解析文本 → prompt 不含该文本

## 7. C12 场景指涉冲突质检

- [x] 7.1 `director_validation_engine.dart` 新增 C12：从 `actionZh` 抽取场景类名词（30 词枚举表），若抽到的名词既不在 `scene.name` 也不在 `scene.descriptionZh` 中，报 WARNING
- [x] 7.2 规则 message 指出动作中的场景名词与关联场景名称的不一致；suggestion 提示二选一（改动作或改场景绑定）
- [x] 7.3 `_ShotCard` 的校验提示区展示 C12（既有 `validationIssues` 通道，确认新规则 ID 被消费）
- [x] 7.4 为 7.1 编写单测：`sceneId`=巡城司大牢 + actionZh 含「走出衙门」→ 报 C12；actionZh 为「拱手告辞，转身走向牢门通道」→ 不报

## 8. 回归与验证

- [x] 8.1 跑 `test/tools/ai_video_studio/shot_causality_ordering_test.dart`、`test/dialogue_tts_speaker_and_character_drift_test.dart`、`test/shot_production_modes_and_cinematic_quality_test.dart`，更新受语气/时间轴改动影响的断言
- [x] 8.2 跑 `test/ai_video_studio_prompt_assembler_test.dart`、`test/tools/ai_video_studio/asset_binding_resolver_test.dart`、`test/tools/ai_video_studio/director_validation_causality_test.dart`，确认无回归
- [x] 8.3 全量 `flutter test`，确认无新增失败
- [x] 8.4 `flutter analyze lib/` 确认 0 error
- [x] 8.5 `openspec validate fix-mood-tone-and-timeline-prompt-fidelity --strict` 通过
