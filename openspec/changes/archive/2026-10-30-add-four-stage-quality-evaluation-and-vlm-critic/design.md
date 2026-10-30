## Context

参见 `proposal.md`。目前 `V8WorkToolbox` 的 AI 视频工坊已具备 `C01~C13` 静态导演规则与「连环画预审（Previs）」视图，但在四个核心转化环节仍存在质量评估断层：
1. **小说→剧本**：缺少对不可拍心理词/比喻词的静态扫描与一键视听外化（Show, Don't Tell）工具。
2. **剧本→分镜**：缺少对连续雷同景别（C14）、单镜多动作过载（C15）的量化拦截，且高低位同框冲突分镜只能改写文字，无法一键裂变为标准正反打双镜头（C16）。
3. **分镜→关键帧**：缺少对已生成图片本身的视觉内容验收，用户需肉眼逐张排查“克隆人、悬空站立、丢坐骑”。
4. **分镜→视频与全局概览**：缺少首帧姿态与视频起始动作的衔接门禁（C17），且缺乏直观的四阶段百分制健康度仪表盘。

## Goals / Non-Goals

**Goals:**
- 实现 `ScreenplayQualityEvaluator`：支持本地毫秒级静态扫描剧本可拍性（心理词、比喻词、时空混杂、长句呼吸过载），并提供 AI 驱动的「一键视听外化」改写。
- 扩展 `DirectorValidationEngine`：落地 C14、C15、C16、C17 规则，提供 `StudioQualityScorecard`（四维百分制计分卡），并实现高低位同框分镜「一键裂变为正反打双镜」及过载镜头「一键拆分为双镜」的无损数据变换。
- 实现 `KeyframeVisualCritic`：复用现有的多模态 AI 通道（`AiService` 支持图片 Data URI 输入），对本地 `shot_N.png` 进行结构化 JSON 视觉场记核验，并将结果持久化到 `StudioShot.vlmCriticReport`。
- 在 `ScreenplayPanel` 与 `StoryboardBoard`（含连环画预审视图）完成全链路 UI 闭环接入。

**Non-Goals:**
- 不引入外部重型 Python CV 依赖，视觉审图统一通过现有 OpenAI-Compatible / Gemini / Agnes 多模态 Vision Chat 接口完成，并在无多模态能力或离线测试时提供确定性兜底分析。

## Decisions

### 1. 四维质量计分卡模型 (`StudioQualityScorecard`)
- 将全链路质量拆解为 4 个 0~100 分的独立维度：
  1. `screenplayScore`（剧本可拍度）：由 `ScreenplayQualityEvaluator` 根据不可拍心理词密度、比喻词密度、长句过载率及场次时空纯度计算。
  2. `storyboardGrammarScore`（分镜语法度）：由 C03、C04、C05、C06、C14、C15、C16 的通过率与扣分权重计算。
  3. `keyframeAndPromptScore`（首帧与生图信噪比）：综合生图参考图收窄合规度、关键帧就绪率以及 `vlmCriticReport` 视觉审图得分。
  4. `videoMotionSafetyScore`（视频动势安全度）：由 C07、C09、C10、C13、C17（首帧姿态衔接、无远景口型强求、无负向冲突词、运镜微动作相容）计算。
- 总分 `overallScore` 为四维加权平均，在分镜看板顶栏直接显示为彩色健康度胶囊（如 `质量总分 92 · 四维健康`）。

### 2. 高低落差单镜一键正反打裂变 (`splitVerticalShotIntoReversePair`)
- 当用户在审计弹窗或分镜卡上对高低位同框镜头（如 `#2`：三楼余小白 + 街面骑驴姜七夜）点击「裂变为正反打双镜」时：
  - **镜头 A（原镜号 `#k`）**：保留高位发声者/主动方（如余小白）为主体，景别设为 `mediumCloseUp`（中近景）或 `medium`（中景），摄影调度设为高位俯拍/窗框近景，时长分配为原时长的 55%（若含台词则完整承载该句台词口型），仅绑定高位角色的参考图。
  - **镜头 B（新插入 `#k+1`）**：以低位回应方（如姜七夜）为主体，景别设为 `medium`（中景）或 `full`（全景），摄影调度设为低角度仰拍/街面驻足仰望，时长分配为原时长的 45%（纯反应或简短回应），完整继承 `mountOrVehicle`（如骑在大黑驴上），仅绑定低位角色的参考图。
  - **镜号顺延与片段同步**：原 `#k+1` 及之后的所有分镜 `number` 自动 `+1`，所属 `StudioSegment.shotNumbers` 自动同步更新，确保工程台账零断链。

### 3. VLM 关键帧视觉场记验收 (`KeyframeVisualCritic`)
- 读取 `framesDir/shot_${shot.number}.png`，压缩/编码为 Base64 Data URI。
- 构造结构化场记核验 Prompt，向配置的视觉大模型传入：
  - 预期出场角色列表及人数
  - 预期景别（`shot.shotSize.label`）
  - 预期空间关系（`shot.continuity.screenPosition`、`elevationLevel`）
  - 预期坐骑/道具（`shot.continuity.mountOrVehicle`、`propState`）
  - 画面动作（`shot.actionZh`）
- 要求模型返回严格 JSON：
  ```json
  {
    "score": 85,
    "passed": true,
    "character_count_ok": true,
    "no_clone_artifact": true,
    "spatial_elevation_ok": true,
    "mount_prop_ok": true,
    "shot_scale_ok": true,
    "issues": [],
    "prompt_fix_suggestion": ""
  }
  ```
- 若 `passed == false`，用户点击「采纳建议并重抽」时，系统自动将 `prompt_fix_suggestion` 合入分镜构图约束并触发 `ImageGenTask`。

## Risks / Trade-offs

- **[Risk] 分镜裂变（Shot Fission）导致本地已生成的旧媒体文件镜号错位** → **Mitigation**：在执行裂变插入新分镜时，按倒序（从最大镜号到 `k+1`）自动重命名 `frames/shot_N.png`、`clips/shot_N.mp4` 与 `dialogues/shot_N.mp3` 为 `N+1`，确保已生成的后续镜头资产完美跟随新镜号，不发生张冠李戴。
- **[Risk] 用户当前配置的文本模型不支持 Vision 图片输入** → **Mitigation**：优先调用支持多模态的 Chat 接口；若接口报错不支持 image_url，自动回退为基于分镜元数据与生图 Prompt 的深度静态视觉风险推演，并在报告中注明检验模式。
