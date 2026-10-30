# storyboard-visual-composition Specification

## Purpose
Defines the visual prompt assembly and composition rules for storyboard keyframe image generation, ensuring cinematic actions, scene context, and character consistency are reflected in generated frames.
## Requirements
### Requirement: Action and environment prompt assembly
The system SHALL assemble storyboard shot keyframe generation prompts conforming to the Agnes Image multimodal specification. When multiple reference images (characters and scenes) are supplied, the prompt SHALL explicitly declare each reference image's role (`[参考图角色]`, e.g. "将第一张图作为主要角色，第二张图作为背景场景参考") and specify the preservation constraints (`[需要保留的元素]`, e.g. 保留第一张图的角色身份与第二张图的场景空间布局). The prompt structure SHALL prioritize the shot's core visual action and dramatic focus (`[主体核心动作与视觉焦点]`) in the high-attention front section before static secondary attributes. Environmental details SHALL be extracted from the active `SceneCard` and matched spatial view's detailed Chinese description (`description_zh`) instead of relying on `prompt_en` or falling back to five-character names.

#### Scenario: Generate frame with scripted action and scene
- **WHEN** user triggers keyframe generation for a shot containing action descriptions (e.g. 姜七夜单手按刀，指尖轻敲刀鞘) and an assigned scene with rich Chinese spatial descriptions
- **THEN** system places the action description and camera focal point at the forefront of the prompt and incorporates the scene's detailed Chinese physical atmosphere (e.g. 粗木铁栏水牢、旧案刑架与昏黄油灯) into the environment section

#### Scenario: Multi-image reference role declaration
- **WHEN** keyframe generation is executed with multiple reference images comprising character turnarounds and scene spatial views
- **THEN** system prefixes the prompt with explicit multi-image role directives specifying each image's character or scene role and which identity or architectural layout features must be preserved

### Requirement: Human suppression for establishing and empty shots
The system SHALL inject negative human prompts when a shot does not specify any character IDs, preventing unsolicited human faces from polluting establishing or environmental shots.

#### Scenario: Keyframe generation for empty establishing shot
- **WHEN** keyframe generation is triggered for an establishing shot without any character assigned
- **THEN** system injects human negative constraints (e.g. `person, human, face, character, portrait`) into the negative prompt to guarantee a clean landscape or scene shot

### Requirement: Character visual anchoring
The system SHALL pass active character reference images (three-view turnaround sheets or face anchors) to the generation adapter, anchoring facial features, hairstyle, and costume. In the text prompt, character descriptions SHALL be formatted as concise identity anchors rather than redundant full-body multi-hundred-word text descriptions that overwhelm visual action weights.

#### Scenario: Keyframe generation for character shot
- **WHEN** keyframe generation is triggered for a shot featuring one or more characters with existing turnaround assets
- **THEN** system binds character turnaround images into the multi-image payload and includes concise character identity anchors in the prompt, preserving high attention weight for the shot's active dramatic action

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`), and SHALL strictly conform to Agnes official mode mutual-exclusion rules: in keyframe mode, reference media fields (`images`, `audios`, `videos`) SHALL NOT be included; in reference mode, `first_frame` and `last_frame` SHALL NOT be included; in text mode, no media field SHALL be included. The adapter SHALL support `last_frame` alongside `first_frame`, and SHALL accept either one alone or both together in keyframe mode. The `size` value SHALL come from the model's supported resolution tiers and the `aspect_ratio` value SHALL come from the supported ratio whitelist; values outside either set SHALL NOT be submitted.

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, `first_frame`, `image`, and `image_url`, and receives successful task dispatch

#### Scenario: Submitting video generation task without keyframe
- **WHEN** user triggers video generation for a shot that has no keyframe image
- **THEN** adapter automatically selects text mode, omits `first_frame`, and submits the prompt to Agnes video model

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: "keyframe"`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, strictly excluding `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model with redundant frame bindings
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, and receives successful task dispatch

#### Scenario: Submitting with both first and last frames
- **WHEN** user triggers video generation with both a first-frame and a last-frame image
- **THEN** adapter submits payload containing both `first_frame` and `last_frame` in keyframe mode, and does not require the first frame to be present when only a last frame is supplied

#### Scenario: Submitting with reference images only
- **WHEN** user triggers video generation with reference images but no first or last frame
- **THEN** adapter selects reference mode, submits the images in the reference media array, and omits `first_frame` and `last_frame`

#### Scenario: Submitting without any media
- **WHEN** user triggers video generation with only a prompt and no media input
- **THEN** adapter automatically selects text mode, omits all media fields, and submits the prompt to Agnes video model

#### Scenario: Requested resolution tier outside model support
- **WHEN** user requests a resolution tier that the selected model does not support (for example `1080P` on the Flash variant)
- **THEN** the adapter submits a tier the model supports, records the snap in the AI log, and does not submit a value outside the model's declared set

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set

#### Scenario: Handling transient upstream rate limits (HTTP 429)
- **WHEN** Agnes video gateway returns HTTP 429 indicating upstream overload
- **THEN** adapter automatically retries up to 4 times with exponential backoff delay, reporting retry progress, before failing the task

### Requirement: Storyboard card and thumbnail null-safe rendering
The storyboard board and thumbnail widgets SHALL cache media file references in local immutable variables during render passes, and SHALL NOT execute unchecked null assertion operator (`!`) on dynamically evaluated file getters.

#### Scenario: Keyframe generation completion and thumbnail update
- **WHEN** keyframe generation completes and triggers state reload on the storyboard board
- **THEN** thumbnail and card widgets render the newly saved frame image without throwing `Null check operator used on a null value`

### Requirement: 中转站 Agnes Video 2.5 Flash 视频生成适配
系统 SHALL 在视频生成适配层提供对 `agnes-video-2.5-flash` 的完整集成。系统 SHALL 向 `POST /v1/videos` 发起任务创建请求（参数包括 `model: "agnes-video-2.5-flash"`, `mode`, `size: "720P"`, `aspect_ratio`, `seconds`, 以及按模式所需的 `first_frame` / `last_frame` / 参考媒体数组，图片接受 Data URI），并异步轮询 `/agnesapi?video_id=...&model_name=agnes-video-2.5-flash` 或 `/v1/videos/{id}`，直到状态为 `completed` 后自动下载成片 MP4 到本地。

#### Scenario: 成功调用 Agnes Video 生成 5 秒视频片段
- **WHEN** 用户或队列针对已有关键帧的分镜触发视频生成
- **THEN** 系统创建视频生成任务并轮询进度，任务完成后将成片 MP4 保存至分镜对应目录并将分镜状态标记为已完成

#### Scenario: Flash 型号提交非 720P 档位
- **WHEN** 用户为 `agnes-video-2.5-flash` 请求 `1080P` 或 `2K` 档位
- **THEN** 系统 SHALL 提交 `720P` 并在日志中记录该吸附，SHALL NOT 提交会导致上游 HTTP 400 的档位值

### Requirement: Agnes gateway resilience and transient error retry
The video generation adapter for Agnes AI SHALL automatically retry task dispatch upon receiving transient upstream gateway errors, including HTTP 429 (rate limiting / saturation), HTTP 502/503/504 (bad gateway / queue full), and HTTP 400 with message indicating missing first_frame/last_frame caused by gateway parameter drop, applying exponential backoff with jitter to rotate to a healthy upstream node.

#### Scenario: Gateway routing to node with dropped parameters
- **WHEN** video dispatch request hits an upstream gateway node that drops `first_frame` and returns HTTP 400 with `keyframe 模式需要 first_frame 或 last_frame`
- **THEN** adapter catches the transient gateway failure, waits with backoff, and retries the dispatch, successfully rotating to a healthy upstream node without crashing or immediately aborting the user task

#### Scenario: Upstream video queue saturated
- **WHEN** upstream video queue returns HTTP 429 or HTTP 503 indicating queue saturation
- **THEN** adapter logs the queue status, informs the user via progress updates, and retries up to the configured retry threshold before declaring failure

### Requirement: 首尾帧参考图尺寸守卫

系统 SHALL 对提交给 Agnes 视频模型的首帧与尾帧执行相同的尺寸校验：单边小于 256 像素或大于 5760 像素的图片 SHALL 被拒绝并说明原因；超过传输上限的图片 SHALL 在提交前被等比缩放并重新编码。首帧与尾帧 SHALL 使用同一套守卫逻辑，而不是尾帧跳过校验。

#### Scenario: 尾帧尺寸过小

- **WHEN** 用户提交一张边长为 200 像素的尾帧
- **THEN** 系统 SHALL 拒绝该请求并提示图片尺寸不满足模型要求，SHALL NOT 提交请求

#### Scenario: 超大首帧与尾帧

- **WHEN** 用户提交两张 4000×6000 像素的首帧与尾帧
- **THEN** 两张图 SHALL 都被等比缩放至传输上限内并重新编码后才提交

### Requirement: 道具素材指代与正向提示词编译
系统提示词组装引擎（`PromptAssembler` & `AssetBindingResolver`）SHALL 支持解析分镜中的道具绑定。在参考图模式（`reference`）下，系统 SHALL 为每个选中的道具素材分配全局连续的 `<Picture N>` 编号（顺序为：角色素材 ➔ 道具素材 ➔ 场景素材）。

在组装最终提示词时，系统 SHALL 在【素材指代】段中输出道具标识（如 `<Picture 3> = 杀生剑（道具）`），并在出场主体/关键物描述中注入该道具的视觉特征与操作交互。

#### Scenario: 分镜包含角色、道具与场景时的素材编号连续编排
- **WHEN** 分镜绑定了 1 个角色（选 1 张图）、1 个道具（选 1 张图）和 1 个场景（选 1 张图）
- **THEN** 提示词引擎 SHALL 按顺序生成：`<Picture 1> = 角色名（主体）`、`<Picture 2> = 道具名（道具）`、`<Picture 3> = 场景名（场景）`，编号无空缺且与提交到模型 media 数组严格同序

#### Scenario: 首尾帧 keyframe 模式下收敛道具与角色克隆
- **WHEN** 分镜处于首尾帧（`keyframe`）模式并执行提示词净化
- **THEN** 系统 SHALL 剥离 `<Picture N>` 道具标签与重复构图描述，保留核心交互动势，防止视频生成模型二次多重绘制道具或克隆实体

### Requirement: Storyboard task error log inspection and clipboard copy
The storyboard board and task queue drawer SHALL provide a detailed log inspection dialog for failed tasks, displaying full unabridged error text and execution metadata, and allowing users to copy the entire error log to the clipboard with visual confirmation.

#### Scenario: Inspecting failed shot generation error
- **WHEN** user clicks on the error indicator on a shot card or a failed task in the queue drawer
- **THEN** system opens a modal dialog displaying the full error message in selectable text with a dedicated copy button
- **WHEN** user clicks the copy button
- **THEN** system writes the complete error text to system clipboard and displays a confirmation notification

### Requirement: Full-lifecycle AI logging for video generation
All video generation adapters SHALL log request dispatch, upstream response, and error details through `AiLogger`, ensuring video generation operations are transparently recorded alongside image generation in application logs.

#### Scenario: Video generation request logging
- **WHEN** a video generation task is initiated
- **THEN** adapter logs the target provider, model, endpoint, and prompt summary to `AiLogger`
- **WHEN** an error occurs during video generation
- **THEN** adapter logs the full error status code and response payload to `AiLogger`

### Requirement: Robust first frame payload handling for Agnes video
The `AgnesVideoAdapter` SHALL format the initial frame image data to be compatible with upstream Agnes video gateways, ensuring the keyframe mode payload includes valid first-frame attributes accepted by the endpoint without triggering `first_frame` missing rejections.

#### Scenario: Dispatching Agnes video with keyframe image
- **WHEN** user generates a video clip for a shot with a valid keyframe image
- **THEN** adapter formats the payload to satisfy the gateway's first-frame parameter requirements and begins polling

### Requirement: Scene and spatial reference injection for keyframes
The system SHALL resolve the active `SceneCard` matching the shot's `sceneId` and pass it to the keyframe generation task runner (`ImageGenTask`). The task runner SHALL automatically resolve the corresponding spatial view reference image (e.g. `spatial_front`, `spatial_back`) and inject it into the image generation adapter's reference images list alongside character turnaround images.

#### Scenario: Trigger keyframe generation from storyboard board
- **WHEN** user triggers keyframe generation for a shot bound to a scene card with spatial profile images
- **THEN** system resolves the scene card, extracts the matching spatial profile image path, and includes it in `ImageGenRequest.referenceImages` so the image model receives both character and scene references

### Requirement: Environment-aware style token filtering
The system SHALL inspect the shot's scene setting (e.g. indoor, underground jail, secret chamber vs. open mountain/outdoor) and filter out contradictory landscape tokens (such as `云海雾气`, `广阔天地`, `日落霞光`) from the positive style baseline when generating indoor or subterranean keyframes, replacing them with appropriate interior lighting and enclosed atmosphere descriptors.

#### Scenario: Generating indoor jail keyframe with generic donghua style
- **WHEN** keyframe generation is triggered for a subterranean jail scene under a Chinese fantasy style preset that includes `云海雾气`
- **THEN** system automatically suppresses outdoor cloud and mountain tokens from the prompt and injects indoor ambient lighting tokens (e.g. `昏暗油灯微光`, `阴冷潮湿质感`)

### Requirement: 竖屏 9:16 视听语法与分镜工业化约束

系统在将文学剧本拆解为五维分镜时，SHALL 针对 9:16 竖屏短剧的视觉特性强制执行以下工业约束：
1. **景别偏好**：优先采用中近景、特写与半身景（占比不低于 70%），凸显角色表情与微动作；严格限制远景与大全景的使用频率，避免竖屏人物过小导致面部细节崩坏。
2. **单镜头主体数量限制**：单镜头画面的核心人物数量 STRICTLY 控制在 1~3 人以内；若剧本场次为 4 人以上群像冲突，拆镜引擎 MUST 自动将其拆解为“全景建立环境 ➔ 发言者单人特写 ➔ 对手反应近景 ➔ 双人正反打”的连续镜头组。
3. **字幕安全区预留**：画面底部 1/5 区域判定为字幕保留区，画面主体动作与关键视觉道具必须定位于画面中上部黄金分割区，禁止将关键信息放置在底部易被字幕遮挡的位置。
4. **镜头运动平缓性**：优先规划固定机位、缓慢推拉（push-in / pull-out）或水平平移追踪（pan / track）；禁止生成 360 度剧烈旋转或复杂多轴长镜头，防止下游视频生成模型出现严重画面撕裂畸变。

#### Scenario: 四人群戏自动拆解为特写与正反打
- **WHEN** 剧本场次为一家四口同桌争吵
- **THEN** 系统拆出的分镜包含桌前全景交待关系、父亲怒目单人特写、母亲低头抹泪近景以及儿女对视正反打，无四人并排挤在一个竖屏镜头内的畸变画面

#### Scenario: 底部字幕安全区保护
- **WHEN** 生成分镜画面的构图与站位描述
- **THEN** 画面构图描述明确将人物主体胸部以上与关键持握道具锚定在画面上部 60% 区域，底部预留字幕空间

### Requirement: 正负向工业提示词模板装配

系统在为每个分镜组装发送给图生图或视频生成引擎的提示词时，SHALL 采用分层模块化装配规范：
1. **正向提示词**：由全局美学前缀（如“UE5渲染，3D国漫，电影级光影，8K，竖屏9:16”）、绑定角色外观锚点词（发型、固定服饰、配饰）、场景七方位特征词以及本镜头具象微动作词按层级拼接而成；
2. **负向提示词**：自动注入可配置的工业级防崩坏词库（如“低质量, 模糊, 变形, 多手指, 面部崩坏, 水印, 文字, 扭曲, 比例失调, 多余肢体”）。

系统 SHALL 支持用户在提示词配置中心全局自定义该正负向装配模板。

#### Scenario: 自动拼接角色锚点与工业级负向词
- **WHEN** 为含有主角姜七夜的拔刀分镜组装生图 Prompt
- **THEN** 组装结果自动前置全局国漫 3D 美术风格，中段注入姜七夜的玄色绣金道袍与冷峻面容特征，后段拼接拔刀动作，并在负向提示词中注入全量防畸形负向词

### Requirement: Long-form novel deconstruction timeout resilience
The system SHALL allocate extended timeout thresholds (at least 240 seconds) for deep novel deconstruction tasks (`novelMasterExtraction` and `novelEpisodeSegmentation`), preventing premature client-side `TimeoutException` aborts when using reasoning and long-context LLMs.

#### Scenario: Importing long novel text with reasoning model
- **WHEN** user imports novel text into Idea Incubator and the underlying model takes more than 120 seconds to produce structured JSON assets
- **THEN** system maintains the connection up to the extended timeout threshold without throwing `TimeoutException after 0:02:00.000000`, successfully parsing and saving characters, scenes, and episodes

### Requirement: Live elapsed time display during novel import
The system SHALL provide a live updating ticker showing elapsed seconds during the novel deconstruction phases, giving visual confirmation of ongoing background processing.

#### Scenario: User imports novel file
- **WHEN** novel import starts
- **THEN** the UI displays the current phase along with an increasing elapsed seconds counter (e.g. `已耗时 12s`)

### Requirement: 封闭与室内场景室外冲突词净化
在构建场景卡底图提示词（`ScenePromptBuilder`）及分镜生图提示词（`PromptAssembler`）时，系统 SHALL 对封闭空间、室内及地下场景进行环境词净化：
1. **自动判定**：系统 SHALL 依据场景名称、场景描述与动作文本通过封闭空间判定规则（`isEnclosedScene`）识别室内、大牢、地牢、密室、厢房等场景。
2. **室外冲突剔除**：当判定为封闭场景时，系统 SHALL 自动从时代题材锚点（`era.environmentAnchor`）与风格词（`styleTokens`）中滤除室外强相关词（包括 `云雾缭绕`、`奇峰仙山`、`古建亭台楼阁`、`云海雾气`、`开阔天空`、`苍穹`、`长街` 等）。
3. **室内环境光注入**：滤除后，系统 SHALL 补充室内局部微光、环境阴影与真实封闭空间材质描述，杜绝地牢场景生成时出现室外天空与浮空仙山。

#### Scenario: 仙侠修真题材下生成巡城司大牢场景底图
- **WHEN** 剧集时代题材为“仙侠修真”（默认带云雾奇峰亭台锚点），用户生成“巡城司大牢”场景底图
- **THEN** 系统自动识别该场景为地牢封闭空间，剔除云海、奇峰与仙山亭台词汇
- **AND** 生成的场景底图提示词仅包含青石、囚室、铁栏、油灯及室内阴影，无露天仙山元素

### Requirement: 多参考图提示词轻量化与动作权重强化
当生图任务向模型提供角色三视图或面部参考图时，系统 SHALL 实行提示词轻量化策略，强化核心动作注意力权重：
1. **剥离静态外观长文**：系统 MUST NOT 在提示词中重复堆砌角色在 IP 主库中的数百字常驻容貌、五官、体格及全身默认服饰描述（`c.basePromptPositive`）；角色视觉特征交由输入参考图像承载。
2. **仅保留即时差异与状态**：角色字段仅保留角色名称、当前镜头激活的形态变体增量描述（`variation.positiveDelta`，如战损、蒙面），以及即时神态。
3. **强化核心动作焦点**：节约出的提示词空间与注意力权重 SHALL 倾斜给分镜核心视觉动作（`actionZh`）与即时对白神态，确保模型优先呈现分镜中的具象微动作与关键剧情点。
4. **动态取景解绑**：多图合成指令中对场景参考图的保留要求，SHALL 明确为保留建筑材质与环境光影风格，同时允许镜头自由根据分镜动作取景，MUST NOT 强制锁死参考图的绝对视角与居中陈设。

#### Scenario: 多参考图分镜生图剥离主库静态容貌
- **WHEN** 为分镜 1（姜七夜与老王在大牢值房）生成关键帧，且已传入姜七夜与老王的三视图参考图
- **THEN** 组装的提示词中不再包含“二十岁出头剑眉星目身着玄青色巡城司...”及“五十余岁面容枯瘦褶皱...”的长篇静态描述
- **AND** 提示词突出强调分镜动作“单手按刀，垂眸立于案前，指尖有节奏地轻敲刀鞘”

### Requirement: 同框人物与画内构图方位解耦
系统生成的提示词分段中，`【同框人物与站位】`（多角色）与 `【出场主体】`（单角色）段落 SHALL 专职描述空间构图，实现外观档案与画内站位解耦：
1. **专职构图职责**：该分段 SHALL 仅输出同框人数、画内主客站位、画面方位（如左侧、右侧、近景、前景、对峙）与视线朝向；
2. **杜绝档案包混入**：该分段 MUST NOT 混入数百字的人物五官容貌与常驻衣着清单；
3. **避免机械站位硬编码**：同框角色的站位关系 SHALL 结合镜头台账或剧情对峙关系生成，避免简单按角色索引机械定死首位永远在前景、次位永远在背景。

#### Scenario: 双人同框镜头仅输出空间站位
- **WHEN** 分镜包含姜七夜与老王两名出场角色
- **THEN** `【同框人物与站位】` 段落生成为简洁的空间构图描述（如“2 people in scene，姜七夜居中案前近景（主景核心焦点），老王立于右侧对峙（次景呼应）”）
- **AND** 段落内无任何关于两人五官长相与服装布料的冗余文字

### Requirement: Segment task isolation and ID compatibility

系统在从 AI 拆镜响应中反序列化分镜片段（`StudioSegment`）时，SHALL 兼容解析 `id` 与 `segment_id` 两种键名，若仅提供数字标号则自动转为 `seg-<N>` 格式，保证每个片段拥有唯一非空标识。
在查询分镜任务状态（`tasksForShot`）时，系统 SHALL 严格仅匹配分镜级任务类型（`frame` 关键帧、`video` 单镜视频），MUST NOT 将片段级任务（`segment`）与单镜任务混淆，防止片段生成触发单镜缩略图的加载动画。

#### Scenario: 片段视频生成不触发单镜缩略图转圈
- **WHEN** 用户点击某个片段的「重新生成」或「生成片段」按钮
- **THEN** 仅该片段卡片的组头操作区展示进度转圈指示器
- **AND** 该片段内各分镜的缩略图及其他片段卡片均保持非运行态，不出现全局转圈

#### Scenario: 兼容 AI 拆镜的 segment_id 字段
- **WHEN** AI 拆镜服务返回包含 `segment_id: 1` 结构的片段列表
- **THEN** 反序列化得到的片段对象具有合法的唯一非空 `id`
- **AND** 多个片段之间不会因 ID 为空字符串而发生状态覆盖与串扰

### Requirement: Micro-texture style baseline and anti-AI-glaze suppression

系统在组装关键帧提示词（`PromptAssembler`）时，SHALL 采用基于物理微质感与电影级漫反射的画风基线替代通用的高光磨皮词汇（如 `masterpiece, best quality`），并在默认负向提示词中显式压制 AI 塑料感、蜡像感与 3D 玩偶脸（如 `plastic skin, smooth doll, airbrushed, wax figure, 3d render doll, uncanny valley`），确保角色生成具备统一且自然的古风/现实材质质感。

#### Scenario: 组装带微质感锁与防塑料感的提示词
- **WHEN** 用户或后台任务触发分镜关键帧生成
- **THEN** 组装出的正向提示词包含皮肤微质感、漫反射与胶片光影约束
- **AND** 负向提示词包含防塑料人脸、防假光滑皮肤与防蜡像感的抑制约束

### Requirement: Shot video generation context enrichment and duration adjustment

系统在触发单镜视频生成（`VideoGenTask`）时，SHALL 将该分镜的视觉动作与剧情描述上下文（`promptZh`）随关键帧底图一同提交给视频模型，避免纯静态底图导致的动作盲目性。
系统在分镜卡片上 SHALL 允许用户查看并调节分镜的目标生成时长，提交时按当前激活视频模型的能力档位（如 4s、6s、8s、10s、12s 等）进行合法性吸附。

#### Scenario: 单镜视频任务携带动作意图上下文
- **WHEN** 用户触发单镜视频生成任务
- **THEN** 提交给底层的视频生成请求（`VideoGenRequest`）中包含该镜的动作意图（`promptZh`）与运镜指令
- **AND** 视频生成时长符合当前选择的档位要求

### Requirement: Worldview tab edit persistence on tab switch
The worldview tab editor SHALL immediately flush any pending debounced changes to disk when the tab is disposed or when text fields lose focus, preventing pasted or typed content from being lost when switching between tabs.

#### Scenario: User pastes worldview content and immediately clicks another tab
- **WHEN** user pastes text into the Worldview text field and clicks the "角色卡" or "场景库" tab within 600ms
- **THEN** system saves the new worldview text immediately before disposing the tab, and reloading the tab displays the saved content

### Requirement: Novel import scope selection
The novel import flow SHALL prompt the user to choose between "Full Novel Deconstruction" (全案解构) and "Single Chapter / Episode Continuation" (单集/章节扩写), allowing users to target an existing episode or append as a new episode without destroying the rest of the series.

#### Scenario: User imports text under single episode continuation mode
- **WHEN** user selects a novel text file in Idea Incubator
- **THEN** system opens a scope dialog where the user can confirm whether this is full novel text or single chapter text, and select the target episode index
- **AND** executing chapter import updates the designated episode synopsis without deleting existing episodes

### Requirement: Incremental IP asset upsert
The project manager SHALL merge newly extracted characters, scenes, and worldview notes non-destructively: matching characters by name to preserve existing custom visual prompts, deduplicating scenes by name, and appending new worldview facts.

#### Scenario: Adding a novel chapter with new and existing characters
- **WHEN** a chapter containing existing character "林长生" and new character "杨德厚" is imported
- **THEN** system retains "林长生" without overwriting custom prompt anchors, and creates a new character card for "杨德厚"

### Requirement: Single-chapter novel adaptation pipeline
The system SHALL ingest full-text single chapter novel content without mechanical prefix truncation, pass the entire chapter narrative into the AI adaptation constraint engine, and produce a structured single-episode synopsis (300 to 500 Chinese characters) capturing opening hooks, conflict escalation, narrative climax, and ending suspense.

#### Scenario: Single chapter novel import without narrative truncation
- **WHEN** user selects a single-chapter novel text file (exceeding 500 characters) and confirms single-episode import
- **THEN** system analyzes the complete chapter text, preserves character conflict and dramatic climax, and saves an adapted single-episode synopsis into the target episode outline without truncating at 480 characters

#### Scenario: Storyboard breakdown receives full-chapter adapted synopsis
- **WHEN** user navigates to the storyboard board for an episode imported from a novel chapter and triggers AI storyboard breakdown
- **THEN** the breakdown engine reads the comprehensive chapter synopsis and generates 8 to 16 shots covering the entire progression from chapter opening to ending cliffhanger

