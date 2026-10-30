## Context

参见 `proposal.md`。当前工坊视频生成流水线在处理多角色同框、高低落差分镜与整场批量生成时，存在三个深层设计盲区：
1. 连续性台账的坐骑与机位属性以分镜为粒度，在组装多角色提示词时未与具体的 `characterId` 绑定，造成盲目全局广播；
2. 视角编译工具过度依赖场景高度字符串匹配，架空了导演决策与明确的机位参数；
3. 批量任务流忽视了模式偏好保护与任务台账上下文作用域，导致运行时状态篡改与跨历史批次混淆。

## Goals / Non-Goals

**Goals:**
- **实体级坐骑绑定**：确保坐骑与交通工具状态严格仅赋予真实的骑乘者，高处或步行角色绝对不带骑乘提示。
- **机位俯仰与视线消解**：确立机位参数（`cameraAngle`）与视线参数（`gazeDirection`）对静态场景标签的绝对优先权，杜绝低角仰拍被误判为高空俯拍。
- **模式确定性与提示词克隆防护**：尊重分镜模式选择，防止批量生成关键帧后静默丢弃角色素材；首尾帧模式下收敛次要角色描述以防模型二次重画克隆人。
- **台账抽屉上下文隔离**：任务抽屉按当前剧集/集号精准过滤，并显示时间戳与内容快照摘要。

**Non-Goals:**
- 不重构 `VideoTaskLedger` 的底层存储结构，保持现有 JSON 数据架构与字段向后兼容。
- 不移除用户手动指定的 `keyframe` 或 `reference` 模式。

## Decisions

### 1. 坐骑实体的归属解析算法（Mount Attribution Resolver）
- **方案**：在 `_buildMultiCharacterStaging` 中增加针对出场角色（`characters[i]`）的归属判定：
  1. 优先比对当前分镜动作描述（`actionZh`）与角色卡名字，若文本中明确包含“`[角色名]...骑`”或“`骑...[角色名]`”，该角色为唯一骑乘者；
  2. 其次，在具有垂直高低落差（`isVerticalHighLow`）的分镜中，高位角色（窗口、天台）被硬性排除骑乘状态，仅处于街面/地面的角色可被附加坐骑状态；
  3. 未被判定为骑乘者的角色，严禁追加 `坐骑状态：骑在...` 指令。
- **替代方案**：在 `StudioShot` 数据结构中增加 `Map<String, String> characterMounts`。
  - *未采用原因*：会破坏现有分镜数据契约并增加额外 UI 配置负担，通过分镜分析与高低落差规则即可在编译器层无损解决。

### 2. 视角俯仰与视线的严格分层优先级
- **方案**：重构 `PromptAssembler.compileGazeAndEyeline`：
  ```
  Priority 1: cameraAngle == 'low_angle' / 'high_angle' (显式机位指令)
  Priority 2: gazeDirection 含有 '仰视'/'向上' 或 '俯视'/'向下' (显式视线朝向)
  Priority 3: elevationLevel (仅作为无上述参数时的兜底参考，且仅对高处实体生效)
  ```
  彻底废弃 `elevationLevel.contains('balcony')` 在 `if-else` 首位直接触发 `isHigh` 的逻辑。
- **替代方案**：强制要求用户在每次拆镜后核对视角。
  - *未采用原因*：属于系统编译器缺陷，应由系统自动消除歧义。

### 3. 视频生成模式确定性与图生视频提示词收敛
- **方案**：
  1. 在 `StudioShot.resolveEffectiveVideoMode` 中：若 `videoMode` 显式设置为 `reference`（非 `auto`），无论是否存在本地关键帧，始终返回 `AgnesVideoMode.reference`；
  2. 在 `PromptAssembler.sanitizeForVideoMode`（`mode == AgnesVideoMode.keyframe`）中：由于首帧画面已固化构图，正向提示词中仅保留主体（Single Subject）的核心微动作与口型对白约束，彻底清洗次要角色的同框构图与外貌站位，阻断视频生成模型在画面上额外生成克隆体的幻觉。

### 4. 任务抽屉当前剧集/集号过滤与批次标记
- **方案**：
  1. `QueueDrawer` 在初始化与加载云端任务（`_loadCloudTasks`）时，读取当前上下文的 `seriesId` 与 `episodeId`，仅筛选出匹配的条目；
  2. `_CloudTaskTile` 标题栏呈现格式化后的任务提交时间（`yyyy-MM-dd HH:mm:ss`），并在副标题中呈现分镜序号与关联动作摘要。

## Risks / Trade-offs

- **[Risk]** 旧项目数据中某些单人分镜没有显式 `cameraAngle` 导致视角判断退化。
  - **Mitigation**: 保留 `gazeDirection`（视线）与 `directorDecisions.cameraStaging`（镜头调度）的关键字提取作为二级兜底。
- **[Risk]** 首尾帧模式下过度裁剪次要角色描述可能导致背景人物静止。
  - **Mitigation**: 仅清洗引导模型重绘人脸的细节描述（如“身着花花绿绿绸衫”、“形象以...为准”），保留“同框者自然倾听、闭口不说话”的连贯性守卫。
