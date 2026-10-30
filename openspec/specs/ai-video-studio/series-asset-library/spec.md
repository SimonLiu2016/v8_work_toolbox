# series-asset-library Specification

## Purpose

三层资产体系（全局公共库 / 连续剧 IP 主库 / 单集制作区），管理角色、场景、风格预设与跨集记忆。
## Requirements
### Requirement: 三层资产体系

系统 SHALL 将资产组织为三层：全局公共库（跨剧通用）、IP 主库（常驻企划专属，含角色卡、场景库、道具、世界观）、单集制作区（单集具体剧本、分镜与音视频生成产物）。IP 主库作为长周期数字资产，其生命周期 SHALL 独立于具体的剧集制作工程。单集制作区中的剧本与分镜被删除或重置时，关联的 IP 主库（角色卡、场景卡、道具卡与世界观设定）及全局资产库（图片、视频片段）SHALL 完好保留不受影响，且可被新剧集项目继续挂载复用。

#### Scenario: 单集制作时引用公共 BGM

- **WHEN** 用户在单集分镜编辑器中为某分镜选择背景音乐
- **THEN** 系统 SHALL 同时展示来自全局公共库的 BGM 列表和来自当前 IP 主库的专属 BGM，并在每项旁边标注来源层级

#### Scenario: 单集覆盖 IP 主库角色形态

- **WHEN** 用户在单集制作区为主角选择了非默认形态（如"战损版"）
- **THEN** 系统 SHALL 仅在该集内所有分镜中应用"战损版"形态的 Prompt 差异词，IP 主库中的角色默认形态不受影响

#### Scenario: 剧集制作清除时保留 IP 主库资产

- **WHEN** 用户删除某剧集或清空制作内容
- **THEN** 系统 SHALL 仅销毁该剧集的单集分镜、剧本及音视频媒体，而该剧集所关联的 IP 主库角色卡、场景卡与道具资产 SHALL 完整保留在 IP 主库中供后续复用

### Requirement: 角色资产卡与形态版本化

系统 SHALL 在 IP 主库中为每个常驻角色维护一张角色资产卡，包含：角色名称、基础生图 Prompt（正向和反向）、基准参考图与基准三视图、绑定的 TTS 音色标识符。系统 SHALL 支持为同一角色创建多个命名形态（State Variation），每个形态仅存储相对于基础 Prompt 的差异词，且每个形态 SHALL 支持持有专属的三视图产物（如 `turnaround_${variation.id}.png`）与形态参考图。

当用户在角色卡上为某一形态生成三视图时，系统 SHALL 自动将角色的默认三视图（`turnaround.png`）或默认参考图作为图生图参考底图（reference image）传递给图像生成引擎，并在提示词中添加同人脸模与五官一致性约束，以确保不同装束、不同年龄时期的角色三视图保持面部身份一致性。系统 SHALL 支持在形态三视图生成时选择标准体态比例（7~8头身）或 Q 版萌系比例（2.5头身）。

#### Scenario: 自然语言角色描述转换为标准 Prompt

- **WHEN** 用户以中文自然语言描述角色外貌并点击"生成 Prompt"
- **THEN** 系统 SHALL 调用 AI 将描述翻译为符合目标生图引擎规范的英文正向 Prompt 和反向 Prompt，并显示预览供用户确认或修改

#### Scenario: 切换角色形态触发分镜 Prompt 重组

- **WHEN** 用户在单集制作区将某角色的激活形态从"默认"切换为"战损版"
- **THEN** 系统 SHALL 将该集所有包含该角色的待生成分镜的 Prompt 自动重组，已生成的历史分镜不受影响

#### Scenario: 为子形态生成三视图时自动继承默认脸模底图

- **WHEN** 用户在角色卡「形态列表」中为「玄铁重铠」或「少年期」形态点击「生成该形态三视图」
- **THEN** 系统 SHALL 自动提取角色的基准 `turnaround.png` 文件，作为 `referenceImages` 输入图像生成适配器，生成的图像文件 SHALL 独立落盘为 `turnaround_${variation.id}.png`，不覆盖基准默认三视图

#### Scenario: 形态三视图支持独立收进资产库

- **WHEN** 用户在形态三视图缩略图上点击收进资产库
- **THEN** 系统 SHALL 将该形态三视图作为图像资产入库，并自动附加角色名、形态名称、三视图标签与当前时代题材标签

### Requirement: 跨集剧情记忆传递

系统 SHALL 为每个 IP 主库维护一份剧情记忆库，包含：各已完成集的剧情摘要、每集末尾的悬念钩子（Hook）文本、人物状态变化记录。当用户创建新一集时，系统 SHALL 自动将前情摘要和上集钩子注入 AI 剧本生成的上下文，用户不可见该注入内容，但可在"前情回顾"面板中查看和编辑。

#### Scenario: 新建后续集时自动注入前情上下文

- **WHEN** 用户在已有 2 集及以上历史的剧集中新建下一集
- **THEN** 系统 SHALL 在 AI 剧本生成请求中自动包含所有已完成集的摘要和最后一集的末尾钩子，AI 生成的新集剧本 SHALL 在内容上与上集结尾衔接

#### Scenario: 手动编辑前情摘要

- **WHEN** 用户在"前情回顾"面板中修改某集的剧情摘要文本
- **THEN** 系统 SHALL 在后续新建集时使用修改后的摘要文本作为上下文

### Requirement: 本地文件目录结构

系统 SHALL 将所有视频工坊数据存储在 `AppSupportDir/video_studio/` 下，目录结构 SHALL 保证 IP 资产层与单集制作层物理隔离：`global_library/`（全局公共资产）、`series_library/<series-id>/`（剧集制作与 IP 映射区，含 `characters/`、`common_scenes/`、`series_profile.json`）、`series_library/<series-id>/episodes/<ep-id>/`（单集制作区，含 `storyboard.json`、`audio/`、`frames/`、`clips/`、`segments/`、`exports/`）。

在场景目录 `common_scenes/<scene-id>/` 中，系统 SHALL 支持 `references/`（常规与方位参考图）与 `panoramas/`（360° 等矩全景母图文件）。

`segments/` SHALL 存放片段级视频产物，文件名 SHALL 包含片段序号；`clips/` 继续存放分镜级视频产物。在执行剧集删除或分集清除时，系统 SHALL 仅定向删除 `episodes/` 及其子目录，严禁递归删除 `characters/` 与 `common_scenes/`。

#### Scenario: 新建剧集项目时目录自动创建

- **WHEN** 用户新建一部连续剧项目
- **THEN** 系统 SHALL 在 `AppSupportDir/video_studio/series_library/` 下自动创建对应目录结构，用户无需手动创建任何文件夹

#### Scenario: 通过系统文件管理器可直接访问原始素材

- **WHEN** 用户在 Finder 中打开 `AppSupportDir/video_studio/` 目录
- **THEN** 用户 SHALL 能按可预期的层级（剧集/集数/音频、帧、片段、导出）直接找到所有生成的原始素材文件

### Requirement: 场景资产卡全景母图与切片多源扩展

系统 SHALL 在 IP 主库的场景资产卡（`SceneCard`）中增加全景母图引用（`panoramaMasterPath`），并为各个空间方位的视角（`SceneDirectionalView`）支持记录生成源（`sourceType: panorama_slice | individual_ai | manual_upload`）。当使用切片引擎填充视角时，系统 SHALL 将视角图片路径自动持久化至场景配置并同步到文件系统。

#### Scenario: 场景卡持久化全景母图与切片路径
- **WHEN** 用户保存包含 360° 全景母图及切片视角的场景
- **THEN** 系统 SHALL 将全景图相对路径写入 `SceneCard` 的元数据中，后续重新打开项目时能完整恢复全景母图与各切片视角的绑定关系

### Requirement: 角色形态三视图生命周期管理

系统 SHALL 在角色卡「形态列表」面板中为每个形态提供独立的三视图状态展示。当形态存在三视图时，系统 SHALL 显示三视图缩略图、点击高清大图预览、删除三视图及重新生成操作；当删除形态时，系统 SHALL 同步清理本地磁盘上对应的形态三视图文件。

#### Scenario: 预览形态专属三视图

- **WHEN** 用户点击某形态卡片上的三视图缩略图
- **THEN** 系统 SHALL 弹出高清图片预览窗口，标题显示当前角色名与形态名

#### Scenario: 删除形态时清理磁盘三视图

- **WHEN** 用户在角色卡编辑界面删除一个已生成三视图的形态
- **THEN** 系统 SHALL 在保存角色卡时同步删除磁盘上的 `turnaround_${variation.id}.png` 文件

### Requirement: 角色三视图体态比例与Q版萌系模式

系统 SHALL 在角色卡三视图生成环节支持体态比例选择（标准全身比例 vs Q版萌系）。标准比例下系统 SHALL 注入成人修长头身比正向锚点，并严格在负向提示词中排他拦截 Q 版（chibi/SD）偏置；Q 版萌系模式下系统 SHALL 注入大头小身萌态正向锚点并拦截成人写实体态。系统 SHALL 支持在角色资产目录下独立保留标准三视图与 Q 版三视图产物，并在生成 Q 版三视图后支持一键创建关联的 Q 版角色形态（Variation）。

#### Scenario: 默认生成标准比例三视图
- **WHEN** 用户在角色卡「生成三视图」操作中选择「标准比例（7~8头身）」
- **THEN** 系统 SHALL 组装标准成人比例正向锚点，并在负向提示词中复合注入排他词（包括 chibi, super deformed, q-version, big head small body 等），产物落盘为 `turnaround.png` 并加入参考图列表。

#### Scenario: 生成 Q版萌系三视图并共存
- **WHEN** 用户在角色卡「生成三视图」操作中选择「Q版萌系（2.5头身）」
- **THEN** 系统 SHALL 组装大头小身萌态正向锚点并在负向中抑制写实成人比例，产物独立落盘为 `turnaround_chibi.png`，在参考图列表中标识为「Q版三视图」，与标准三视图互不覆盖。

#### Scenario: Q版三视图联动创建形态
- **WHEN** 角色成功生成 Q 版三视图且该角色尚未配置 Q 版形态
- **THEN** 系统 SHALL 支持用户一键创建以该 Q 版三视图为参考图的「Q版形态」（CharacterVariation），便于在分镜剧本中直接切换生效。

#### Scenario: 资产库入库差异化打标
- **WHEN** 用户将标准三视图或 Q 版三视图收进资产库
- **THEN** 系统 SHALL 根据文件类型自动为资产追加「标准比例」或「Q版萌系」专属标签，以便在资产选择器中精准检索。

### Requirement: 场景资产卡与七方位空间全息档案

系统 SHALL 为 IP 主库中的每个场景资产卡维护七方位空间全息档案，覆盖正前（`front`，主景与视觉重心）、正后（`back`，反打背景与入口出处）、正左（`left`，左侧立面与采光排窗）、正右（`right`，右侧立面与通道内室）、天顶（`top`，梁木藻井与穹顶天花）、地坪（`bottom`，地面铺装与纹理地毯）以及俯视全景（`topDown`，空间平面拓扑与长宽进深鸟瞰）。

每个方位视图 SHALL 独立包含中文空间环境描述（`descriptionZh`）、英文生图 Prompt（`promptEn`）以及可选的视角参考图路径（`imagePath`）。系统 SHALL 在场景卡编辑界面向用户呈现七方位编辑矩阵，允许用户随时修改任意方位的中文描述与英文提示词。

系统 SHALL 支持用户按需为任一指定方位触发单张生图或绑定本地已有资产图片，并提供「一键生成全息组图 (7视角)」批量生图能力。系统 SHALL 严格遵循用户手动触发原则，不得在解构完成后静默自动启动生图流程，以保障用户生图配额可控。

#### Scenario: 查看与编辑特定方位的空间描述和生图 Prompt
- **WHEN** 用户在场景卡编辑弹窗中切换或展开某一方位（如天顶 `top` 或反打 `back`）并修改其中文描述或英文 Prompt 并保存
- **THEN** 系统 SHALL 更新该场景卡该方位的文本数据并持久化到本地剧集存储，其余方位的描述与已有参考图保持不变

#### Scenario: 按需触发单个方位生图与参考图绑定
- **WHEN** 用户在场景编辑弹窗中点击特定方位（如俯视全景 `topDown`）的生图按钮或绑定已有资产
- **THEN** 系统 SHALL 仅针对该方位生成或绑定图片，将生成/选择的图片路径更新至该方位的 `imagePath`，不影响其他 6 个方位的生图状态

#### Scenario: 一键生成 7 方位全息组图任务
- **WHEN** 用户点击场景编辑面板中的「一键生成全息组图 (7视角)」按钮
- **THEN** 系统 SHALL 依次为该场景中包含有效英文 Prompt 的所有未生图或全部方位提交生图任务队列，任务完成后自动将各视角图片回填至对应方位的 `imagePath`

### Requirement: 全局可配置美学风格与时代题材体系

系统 SHALL 在全局公共资产层提供独立于单剧项目的全局预设存储（`AppSupportDir/video_studio/global_library/presets/` 或 `AppPaths.studioDir/presets/`），包含美学风格预设库（`aesthetic_styles.json`）与视觉时代题材库（`visual_eras.json`）。

系统 SHALL 在初始化时自愈载入出厂内置预设：
1. 美学风格预设库 SHALL 完整收录 8 大美术体系（东方国风、日系二次元、西式CG/3D卡通、科幻赛博废土、实拍电影质感、手工立体质感、暗黑悬疑哥特、小众艺术实验）共 35 套工业级风格，每套风格均包含正向渲染材质锚点（`positiveAnchor`）、专属负面避雷词（`negativeBan`）与推荐画幅。
2. 视觉时代题材库 SHALL 包含东方仙侠、古装武侠、古代宫廷、民国谍战、现代都市、近未来科幻、末日废土、赛博朋克、西幻冒险、中式民俗等全量题材，明确全身服饰锚点、场景环境锚点与时代排他避雷词。

系统 SHALL 支持用户通过全局设置界面查看、筛选、新增自定义预设、微调并保存，以及一键重置为出厂预设。单部剧集在引用全局预设时，SHALL 允许在本剧集世界观内对正向与负向词进行针对性微调覆写。

#### Scenario: 首次启动自愈加载出厂预设
- **WHEN** 应用启动且检测到本地尚未生成 `aesthetic_styles.json` 或 `visual_eras.json`
- **THEN** 系统自动写入包含全部 35 套美学风格及完整时代题材的出厂配置，用户立即可在界面中选择使用

#### Scenario: 用户新增自定义美学风格
- **WHEN** 用户在工坊设置的预设管理界面填写自定义风格名称、所属分类、正向 Prompt 锚点与负向避雷词并保存
- **THEN** 系统将新风格写入全局配置文件并发送实时通知，剧集世界观面板的风格下拉菜单中立即可见并可选用新风格

#### Scenario: 剧集世界观引用并微调全局预设
- **WHEN** 用户在某剧集的世界观标签页选中“UE5 3D国漫·东方玄幻”风格
- **THEN** 界面自动载入该风格的标准正向与负向提示词，用户在文本框内追加针对本剧的个性化补充词后，变更保存于该剧集配置中，全局预设原模板保持不变

### Requirement: 三层负向防崩词装配

在生成角色三视图、场景概念图、分镜关键帧及片段视频时，系统 SHALL 采用三层合并架构自动组装最终发送给生图/生视频引擎的负向提示词（`Negative Prompt`）：
1. 第一层：剧集所选时代题材的排他违禁词（`eraGenre.negativeBans`，如古代题材排斥现代服饰、现代建筑等）；
2. 第二层：剧集所选美学风格的专属负向避雷词（`aestheticStyle.negativeBan`，如 2D 水墨排斥 3D CG 与高反光，写实实拍排斥动漫卡通等）；
3. 第三层：全局通用防崩词（抑制畸形手部、多手指、五官扭曲、低清水印噪点等通用画质瑕疵）。

系统 SHALL 保证各层之间去重拼接，避免重复冗余词占用模型 token 预算。

#### Scenario: 仙侠水墨剧集生图负向词组装
- **WHEN** 剧集配置了“东方仙侠”时代题材与“2D水墨写意国风”美学风格并触发分镜生图
- **THEN** 系统生成的负向提示词中同时包含仙侠时代的现代物禁忌词（modern clothes, sunglasses 等）、水墨画风的 3D 渲染禁忌词（3D, photorealistic, CG 等）以及通用防畸形词，确保生图媒介与题材纯正

### Requirement: 七方位空间全息参考图链控制与抗污染机制

系统 SHALL 在场景“七方位空间全息档案”生图过程中实施严格的参考图拓扑隔离规则，杜绝前序生成的侧向视角（如左侧面）被自动当做后序视角（如右侧面、背面、顶视）的生图参考图而导致视角镜像混淆与参考污染。系统 SHALL 采用“正面主景（Front View）为唯一基准锚点”的单向继承策略：非正面方位在生图时，默认仅允许参考“场景通用基础概念图”与“正面主景”，严禁自动横向交叉参考其他非正面方位图。系统 SHALL 在每个视角的编辑卡片中提供直观的参考图源勾选控制组件，向用户展示当前生效的参考图列表，并允许高级用户自定义勾选或剔除特定参考图。

#### Scenario: 生成右侧面视角时自动隔离左侧面参考图
- **WHEN** 用户已成功生成“正面主景”与“左侧面视角”，接着触发生成“右侧面视角”
- **THEN** 系统 SHALL 自动解析出该次生图的参考图为基础概念图与正面主景图，彻底剔除左侧面视角图片，避免生成的右侧面视角受到左侧构图的污染

#### Scenario: 用户在界面中自定义调整某方位的参考图源
- **WHEN** 用户在某个特定方位卡片（如俯视顶角）中手动展开“参考图源控制”并取消勾选正面主景或指定特定参考素材
- **THEN** 系统 SHALL 遵循用户的勾选设定发起生图请求，并将用户的自定义参考偏好在当前会话中予以保留

#### Scenario: 方位生成产物与场景通用参考图池解耦
- **WHEN** 任意单个方位或 7 视角批处理生成完成
- **THEN** 系统 SHALL 将生成的文件路径绑定至对应方位的 `spatialViews[dir].imagePath`，且 SHALL NOT 自动将其强行塞入场景的通用全局参考图库（`_refs`），防止下一次调用通用生图时造成隐式全局参考图膨胀

### Requirement: 场景资产编辑器宽屏适配与语义分层排版

系统 SHALL 在场景资产编辑器模态面板中采用语义分层布局，且 SHALL 自适应桌面端屏幕宽度（解除移动端默认 640px 约束，最大宽度不小于 1200px 或窗口可用宽度的 90%）。系统 SHALL 将模态窗全局动作（删除场景、保存修改、关闭按钮）固定于顶部标题栏右侧，且严禁在该行并列放置长文本批处理按钮以杜绝水平溢出截断。系统 SHALL 将“AI 全息解构七方位”与“一键生成全息组图”按钮置于“七方位空间全息档案”专属小节栏头部右侧。

#### Scenario: 桌面端窗口下打开场景资产编辑器
- **WHEN** 用户在连续剧“场景”页签中点击任意场景卡片打开编辑面板
- **THEN** 系统 SHALL 以宽屏自适应抽屉（宽度至少 900px 且最高可达 1200px）展示场景详情，顶部标题栏仅包含场景标题与生命周期控制按钮（删除场景、保存修改、关闭），无任何按钮溢出到屏幕之外

#### Scenario: 七方位批量操作入口语义归位
- **WHEN** 用户浏览至“七方位空间全息档案”小节
- **THEN** 系统 SHALL 在该小节标题右侧呈现“AI 全息解构七方位 (仅文字)”与“一键生成全息组图 (7视角)”操作按钮，与下方“场景全部参考图库”的操作栏在视觉与交互层级上保持对齐

### Requirement: 图像生成适配器自动退避重试

系统 SHALL 在调用系统图像模型生成接口（`SystemAiImageAdapter`）时内置自动重试机制。当遇到短暂网络抖动（SocketException / TimeoutException）、服务提供商限流（HTTP 429 Too Many Requests）或服务端异常（HTTP 500、502、503、504）时，系统 SHALL 自动执行最多 3 次重试，并采用指数退避伴随随机抖动延迟（基础间隔 1.5 秒），仅在所有重试耗尽后才判定该次请求失败。

#### Scenario: 触发供应商速率限制自动退避恢复
- **WHEN** 图像生成请求收到上游服务返回的 HTTP 429 速率限制响应
- **THEN** 系统 SHALL 自动等待退避间隔后重新发起请求，不立即向外层抛出致命异常，若在第 2 次重试中成功则正常返回生成图片文件

#### Scenario: 重试耗尽后如实报告原因
- **WHEN** 连续 3 次重试均收到网络超时或服务端错误
- **THEN** 系统 SHALL 记录完整错误上下文日志，并将最终失败原因友好透出给调用方

### Requirement: 七方位空间全息组图故障隔离与断点续跑

系统 SHALL 在执行“一键生成全息组图 (7视角)”批处理任务时对每个方位的生图执行故障隔离。单一方位视角的生成失败 SHALL NOT 导致整个批处理循环中止。系统 SHALL 逐个更新已成功生成并落盘的方位视角，并在所有视角处理完毕后提供汇总反馈；对于生成失败的视角，系统 SHALL 标红提示并支持用户单独重试失败方位。此外，批处理任务 SHALL 脱离单次弹窗界面的生命周期强绑定，关闭弹窗不应丢失已生成的有效图片素材。

#### Scenario: 连续生成中单视角失败不中断其余视角
- **WHEN** 用户触发“一键生成全息组图 (7视角)”，在第 3 个视角（左侧）遭遇服务不可用失败
- **THEN** 系统 SHALL 记录该方位失败并继续生成第 4、5、6、7 个视角，任务结束时将已成功的 6 个视角完整落盘并关联到场景，界面呈现“已完成 6/7，左侧视角生成失败，点击重试”

#### Scenario: 单独重试失败视角
- **WHEN** 用户在全息档案中切换到生成失败的视角并点击“生成此视角图片”
- **THEN** 系统 SHALL 仅针对该方位重新调度生图，成功后自动回填该方位的空镜图片，不影响其他已有方位的素材

### Requirement: 场景库 AI 生成图入口

系统 SHALL 在场景编辑面板提供「生成场景图」操作，接入与道具库一致的图像生成适配器。生成结果 SHALL 存储至场景专属目录，并追加至场景的 `referenceImages` 列表。

#### Scenario: 场景图 AI 生成并收进资产库

- **WHEN** 用户为场景生成 AI 参考图并点击「收进资产库」
- **THEN** 系统 SHALL 将图片以 `AssetCategory.scene` 分类收入资产库，资产库筛选器 SHALL 能按「场景」分类筛出该图

### Requirement: 场景纯净空镜空间与多角度组图生成

系统 SHALL 在 IP 主库场景库中为每个常驻场景提供纯净空镜空间约束与多角度/全景组图生成能力。在生成或更新场景生图 Prompt 时，系统 SHALL 强制注入场景空镜正向特征词（`empty scene, no humans, pure architectural scenery, vacant interior`）与负向人类排除锁（`human, people, person, crowd, man, woman, face, character`），确保场景资产卡不出现具体人物。

系统 SHALL 支持一键为场景卡生成多角度视角组图，组图涵盖：
1. 全景建立镜头（Wide Establishing / Panoramic Shot）
2. 主轴平视全景（Eye-Level Main Interior/Exterior View）
3. 反打/侧方位视角（Reverse Angle / Side Angle View）
4. 局部陈设特写（Detail & Architectural Close-up）

生成后的多视角图片 SHALL 自动存入场景目录下的参考图集合中供下游分镜与大段任务按需引用。

#### Scenario: 场景生图自动阻绝人物并生成空镜
- **WHEN** 用户在场景卡编辑弹窗中点击“AI 生成场景图”
- **THEN** 系统在调用生图适配器时自动拼接纯净空镜提示词与人类负向排除词，生成的图片为不包含人物的纯建筑空间与环境光影。

#### Scenario: 一键生成多角度场景包
- **WHEN** 用户点击“生成多角度场景组图”
- **THEN** 系统依次并发或按序生成全景、主视、反打与特写视角的一整套图片，并追加至该场景的参考图库中。

### Requirement: 连续剧全局会话与时代题材状态同步

系统 SHALL 在全局 `StudioSession` 中维护当前激活的剧集对象。当在 IP 主库修改世界观、时代题材（`eraGenre`）、全局风格锁等属性并落盘时，`StudioSession` SHALL 在剧集 ID 相同时更新内存中保存的最新剧集对象，并向全局监听器广播通知，且 SHALL NOT 误重置当前选中的集（`episode`）。各面板（如 `SeriesPage`）在收到通知或切换 Tab 时，SHALL 呈现内存中最新的剧集属性与标签选中状态。

#### Scenario: 切换时代题材标签后切 Tab 状态保持
- **WHEN** 用户在「世界观」选项卡中选中一个视觉时代题材（如“仙侠修真”），并切换到「角色卡」或左侧「分镜看板」后再切换回「世界观」
- **THEN** 界面上的“仙侠修真”标签仍处于高亮选中状态，且下方展示对应的时代服饰与道具锚点。

### Requirement: 剧集库分集展开与快捷管理
The system SHALL 在剧集库列表页支持展开查看各剧集下的分集清单（第 1..N 集），并支持在卡片内直接创建新分集。

#### Scenario: 展开分集列表与新建
- **WHEN** 用户在剧集卡片上点击展开分集
- **THEN** 系统列出所有子集标题与分镜数，并提供「+ 新建第 N 集」按钮

### Requirement: 场景卡全量编辑与分镜联动
The system SHALL 支持对场景库中的场景项进行完整编辑（包括场景中文描述、AI 生成英文提示词与垫图参考图），并在分镜卡片上可被下拉选择并生效到生图 Prompt 中。

#### Scenario: 场景详情编辑
- **WHEN** 用户点击场景库中的某一场景卡片
- **THEN** 展开编辑面板，允许修改中文环境描述、点击生成英文 Prompt 并上传参考图

#### Scenario: 分镜关联场景
- **WHEN** 用户在分镜卡片上选择该场景
- **THEN** 该场景设定的提示词与视觉约束自动合成至该分镜的生图 Prompt 中

### Requirement: 视觉风格词预设标签点选
The system SHALL 在世界观设定中的全局风格词输入区域提供常见影视风格标签 Chip，供创作者快速选择或组合。

#### Scenario: 点击风格标签快捷填入
- **WHEN** 用户点击「电影质感」或「日系动漫」预设 Chip
- **THEN** 对应的专业风格修饰词自动追加到全局风格词输入框中

### Requirement: 系统全局 AI 音色优先接入与试听
The system SHALL 在世界观与角色卡中的 TTS 音色选择优先接入软件全局配置的 AI 语音供应商与模型，提供直观的下拉列表，并支持就地试听音频效果。

#### Scenario: 系统音色下拉与试听
- **WHEN** 用户打开音色选择下拉菜单
- **THEN** 系统列出全局 AI 设置中的已启用 TTS 音色（及内置 Edge-TTS 兜底），点击「▶ 试听」可即时播放试听样例

### Requirement: 多集前情回顾时间线与生成
The system SHALL 提供按集排列的前情回顾编辑列表，支持针对任意分集一键 AI 提炼剧情摘要与下集钩子，并支持创作者手动修改保存。

#### Scenario: 为任意分集更新前情记忆
- **WHEN** 用户在集数与前情标签页中编辑第 2 集的前情回顾
- **THEN** 修改即时落盘，在后续基于该集生成或扩写剧情时自动生效

### Requirement: 场景纯净空镜生图与严格人物抑制

系统 SHALL 在执行任何场景生图（包括单场景主图生成、七方位空间生图与多角度场景包生成）时，对生图提示词进行全链路空镜加固与零人物严格抑制，确保产出的场景资产为纯净的物理置景与环境底板。

1. **肯定式无人空镜专有约束**：系统 SHALL 使用肯定式建筑与环境摄影术语（`completely uninhabited, vacant architecture, deserted, empty background plate, architectural still life, unoccupied room, void of human presence, motionless stillness`）替换或重构传统 `no humans, no people` 等容易被扩散模型注意力机制逆向激活的否定式短语。
2. **首尾双重夹逼结构（Prompt Sandwiching）**：系统 SHALL 将肯定式空镜背景板约束分别注入至正向 Prompt 的最前端（最高注意力权重区）与最末端（收口固化区），将环境细节与镜头视角包裹在中间。
3. **生图提示词人物实体自动清洗（Scrubbing）**：系统 SHALL 在将 `basePrompt` 送往图像生成模型前，自动过滤与清洗其中包含的人称代词、角色称谓、人物实体名词与交互动作词汇（如 `human, people, person, crowd, man, woman, character, figure, pedestrian, someone, vendor, monk, soldier, sitting, walking, talking` 等），将其替换或降级为纯物理构件与环境特征。
4. **适配器层负向词透传与保全**：所有图像生成适配器（包括 Agnes、SenseAudio 以及 OpenAI 兼容协议适配器）在向底层服务发起生图请求时，SHALL 完整组装并传递包含人物抑制词库的 `negative_prompt` 参数，不得静默丢弃。

#### Scenario: 场景提示词首尾夹逼与肯定式构建

- **WHEN** 用户为某场景触发单视角或批量七方位生图
- **THEN** 系统组装的正向生图 Prompt 头部必须包含 `empty background plate, completely uninhabited, vacant architecture`，尾部必须包含 `unoccupied space, zero people, architectural stillness, deserted room`，且不得包含 `no humans` 等具有反向激活风险的敏感词根

#### Scenario: basePrompt 自动剥离人物实体词汇

- **WHEN** 场景的原始英文 Prompt 包含如 `"bustling street with pedestrians and shopkeeper talking"` 等带有人物活动与角色的描述
- **THEN** 经过空镜清洗器后，生图请求中的实际描述将被安全过滤为纯环境置景（例如 `"traditional street with shopfronts and architectural details"`），消除人物实体引导

#### Scenario: 底层图像适配器负向词全透传

- **WHEN** 系统通过 Agnes、SenseAudio 或 OpenAI 兼容图像适配器生成场景空镜
- **THEN** 发往 API 接口的 HTTP 请求体中 SHALL 包含 `negative_prompt` 字段，且内容包含 `human, people, person, crowd, man, woman, face, character, figure, silhouettes, body`

### Requirement: 场景空间视角宽画幅生成与规格自定义

系统在生成场景空间视角图（包括单视角生成与 7 方位空间批量生成）时，默认生图规格 SHALL 为 2K · 16:9 宽画幅，MUST NOT 缺省参数退回 9:16 竖屏短剧默认值。

系统在场景空间全息视图编辑界面与批量生成操作区 SHALL 提供生图规格选择控件，支持用户自由指定分辨率档位（1K / 2K / 3K / 4K）与宽高比（16:9 / 21:9 / 9:16 / 1:1 / 4:3）。

#### Scenario: 默认生成 16:9 宽画幅场景图
- **WHEN** 用户对某个场景的单视角或批量 7 方位触发「生成视角图」
- **THEN** 系统提交给图像模型的生图请求中 SHALL 显式包含 16:9 对应的宽屏分辨率参数（如 2624x1472 或 2K 16:9），产出宏大宽画幅场景图

#### Scenario: 针对竖屏短剧特写手动切换 9:16 场景
- **WHEN** 用户在场景视角编辑区手动选择 9:16 竖屏比例并生成
- **THEN** 系统提交的生图请求 SHALL 适配为 9:16 竖屏尺寸，满足特定竖屏局部场景构图需求

### Requirement: 剧集主档案持久化默认画幅比例与分辨率预设
系统 SHALL 在连续剧 IP 主库档案（`series_profile.json`）中持久化该剧集的默认画幅比例（`defaultAspectRatio`，默认支持 `9:16`、`16:9`、`21:9`、`4:3`、`1:1`）与默认分辨率档位（`defaultResolution`，如 `2K`、`1K`、`4K`、`720P`、`1080P`）。系统 SHALL 在世界观与剧集设定面板中提供可视化选择界面供用户设置与保存，所有新建集与未指定规格的分镜 SHALL 自动继承该默认设置。

#### Scenario: 剧集设定保存默认画幅为 16:9 宽幅
- **WHEN** 用户在连续剧设定面板中将默认画幅比例切换为 16:9 横屏并保存
- **THEN** 该设置被持久化至 `series_profile.json`，当前剧集所有未单独指定比例的分镜与新创建的分镜自动以 16:9 规格推进制作

