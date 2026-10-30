## Why

视频生成请求体里浮出一批「软件拼错了但用户改不了」的问题，根源分两类。

**一类是字段语义被混用。** `shot.mood` 的本意是画面氛围（驱动 BGM 匹配与运镜推荐），`buildVideoGenPrompt` 却直接把它当台词语气写进 prompt——AI 拆镜把 mood 填成 `warm`（温馨）时，一句「你！你站住！反了你了！」就被标注成"语气：温馨"送给模型。画面氛围与人物情绪本是两个维度，挤在一个字段上必然打架。

**另一类更根本：AI 一言堂。** 请求体里的每个字都来自 AI 生成或程序推导，界面却几乎不给你改的入口。核对结果：

```
情绪/语气（mood）   → 7 处引用、0 个输入控件，只能看
因果时间轴          → temporalEvolution 只在 _DirectorDecisionsPanel 只读展示
景别/时长/场景/台词 → 有控件
```

`mood` 和 `temporalEvolution` 恰好是两个「AI 写错就直接毁掉成片、用户毫无办法」的字段。AI 生成的不一定准确，那就必须让人能改。

此外还有三处 prompt 保真问题：`temporalEvolution` 解析不出秒数时会被原样塞进 prompt（「相位说明：动作处于启动及推进相位」——模型看不懂的噪声）；`<Picture N>` 挂在时间段末尾，写法有歧义；场景参考图没有声明「不作人脸参考」，有被模型当人物图刷的风险。

## What Changes

- **分镜卡新增「情绪」下拉**：`ShotMood` 七个值可直接选改。当前 mood 只读。
- **`_DirectorDecisionsPanel` 的「时间演变」改为可编辑**：现在是 `_buildDecisionRow` 只读文本。改为可编辑输入，改动即时写回 `directorDecisions.temporalEvolution`。
- **语气与氛围解耦**：`buildVideoGenPrompt` 不再用 `shot.mood` 当台词语气。改为从 `dialogue` 文本中解析情绪提示（如「（压低声音，咬牙）」）；解析不到时**不写语气**——留白好过错语气。
- **时间轴去掉「相位说明」噪声**：`temporalEvolution` 仅在能解析出显式秒数分界时参与时间分配；解析不出时静默丢弃，不再原样进 prompt。
- **`<Picture N>` 写法改为行内前置**：从「时间段末尾」改为「主体名之后紧跟」——`姜七夜（<Picture 1>）拱手一拜`。时间区间只标时刻，不挂图片。
- **场景参考图显式声明用途**：【素材指代】中场景行追加「仅场景环境参考，不作为人物人脸参考」。
- **新增 C12 质检规则**：动作描述里出现的场景名词与 `sceneId` 指向的场景卡名称/描述不符时给出 WARNING（如「走出衙门」配「巡城司大牢」），在消耗额度前拦截。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `ai-video-studio/shot-production`: 分镜级视频提示词的语气来源变化（不再取自 mood，改从台词解析，解析不到则留空）；时间轴去掉相位说明噪声、素材编号改为行内前置；场景参考图须声明不作人脸参考；「情绪」从只读字段变为用户可改字段。
- `ai-video-studio/script-workshop`: 「五维导演决策」的时间演变字段从只读展示变为用户可编辑，且其进入视频提示词的条件收紧为「能解析出显式秒数」。
- `ai-video-studio/shot-continuity`: 质检规则集新增 C12——动作中的场景名词与关联场景卡不符时警告。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/prompt_assembler.dart` — 语气来源、时间轴拼装、`<Picture N>` 位置、场景声明。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart` — 情绪下拉、时间演变为可编辑。
- `lib/tools/ai_video_studio/services/director_validation_engine.dart` — 新增 C12。
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` — 拆镜模板的语气提示要求（已有，需确认措辞与解析规则对齐）。

**风险**
- 语气改留白后，部分分镜的 prompt 里不再有语气词——这是刻意选择（错语气比没语气更糟），但观感上 prompt 会变短。
- `temporalEvolution` 静默丢弃后，若它本就含有效信息但格式不被解析，那段信息会消失。缓解：解析规则覆盖「前N秒」「N秒」两种主流写法，且用户现在可直接编辑该字段。
