# Technical Design: add-character-turnaround-proportion-and-chibi-mode

## Context

见 `proposal.md`。当前 `CharacterTurnaroundPrompt` 仅负责视角布局、身份一致性、时代题材服饰锚点与风格锁的串联，尚未建立体态骨骼比例与 Q 版排他互斥机制。

在 `lib/tools/ai_video_studio/ui/series_page.dart` 中，角色卡生成三视图为单点固定触发，产物唯一落盘于 `characters/<id>/turnaround.png`。

## Goals / Non-Goals

**Goals:**
1. 建立 `CharacterTurnaroundProportion` 体态枚举与双向提示词互斥字典；
2. 升级 `CharacterTurnaroundPrompt`，在生成时将体态比例作为最高优先级骨架约束注入；
3. 角色卡三视图操作升级为 `PopupMenuButton` 下拉，支持一键触发标准比例或 Q 版萌系生成；
4. 标准三视图与 Q 版三视图共存展示，提供专属标识徽标；
5. 生成 Q 版三视图后，支持一键创建绑定的「Q版形态」（`CharacterVariation`）；
6. 资产库入库自动打标「标准比例」或「Q版萌系」。

**Non-Goals:**
1. 改变剧集模型结构（体态是三视图生成与角色形态维度的属性，无需污染 `StudioSeries`）；
2. 影响道具与场景生图（道具与场景不涉及人体头身比）。

## Decisions

### D1: 下拉菜单触发 (`PopupMenuButton`) vs 阻断式确认弹窗
- **选择**: 在角色卡控制栏采用 `PopupMenuButton<CharacterTurnaroundProportion>`，主按钮文字动态显示生成状态，点击展开：
  - `● 生成标准比例三视图（7~8头身，默认）`
  - `○ 生成 Q版萌系三视图（2.5头身，纸人/内心戏）`
- **对比**: 弹窗虽然信息展示完整，但每次生成三视图都需要额外点击“确定”关闭，打断创作者快速试错心流；下拉菜单既保持了默认推荐路径，又实现了零弹窗一键启动。

### D2: 产物落盘命名与向后兼容
- **选择**:
  - 标准比例：继续写 `turnaround.png`（与旧版本完全兼容）；
  - Q 版萌系：独立写 `turnaround_chibi.png`。
- **机制**:
  - `referenceImages` 识别三视图时采用 `refName == 'turnaround.png' || refName.contains('turnaround')`；
  - 缩略图角标根据文件名精确区分：`refName.contains('chibi')` 展示粉色「Q版三视图」徽标，其余展示主色「三视图」徽标。两者互不覆盖、共存于参考图栏中。

### D3: 提示词层面的强正向锚定 + 强负向排他
- **选择**:
  - `standard`:
    - 正向注入: `standard human proportions, 7-head-tall proportion, tall and slender figure, mature adult anatomy`
    - 负向排他: `chibi, super deformed, SD, q-version, big head small body, oversized head, 2-head-tall, 3-head-tall, toddler proportions, cartoon doll, miniature figurine, funko pop`
  - `chibi`:
    - 正向注入: `chibi style, cute Q-version, super deformed, 2.5-head-tall proportion, oversized round head, petite body, short cute limbs, adorable anime chibi figure`
    - 负向排他: `realistic adult proportions, tall stature, 8-head tall, mature realistic anatomy, elongated limbs, sharp mature face`
- **对比**: 若仅在正向写 `chibi` 或仅在负向写 `chibi`，二次元扩散模型在面对 `character sheet` 标签时仍有 20%~30% 的概率出现四不像。必须正负向双向卡死。

### D4: 与角色形态（CharacterVariation）联动流转
- **选择**: 当用户生成 `turnaround_chibi.png` 成功后，检查该角色的 `variations` 是否已存在名字包含“Q版”或“纸人”的形态；若不存在，在卡片形态列表旁显示高亮快捷按钮「设为Q版形态」，点击即可自动追加一条：
  ```dart
  CharacterVariation(
    id: 'var_chibi_${DateTime.now().millisecondsSinceEpoch}',
    name: 'Q版纸人/化身',
    triggerCondition: '纸人化身 / 内心戏 / 搞笑剧情',
    promptModifierPositive: 'chibi style, super deformed, 2.5-head-tall proportion',
    promptModifierNegative: 'realistic adult proportions, tall stature',
    referenceImages: ['turnaround_chibi.png'],
    active: false,
  )
  ```
- **价值**: 《师兄啊师兄》模式中，用户后续在分镜画板中直接在角色下拉里勾选该形态，分镜生图与参考图就会自然绑定 Q 版化身，无需手动配置。

## Risks / Trade-offs

- **[Risk]** 用户先点了标准再点 Q 版，资产库入库按钮应该收哪张？
  - **Mitigation**: 点击「三视图入库」时，若目录下同时存在标准与 Q 版，弹出或默认收进最新生成的一张，或在三视图预览大图弹窗内直接提供「入库」按钮。在角色卡主界面，「三视图入库」遍历所有存在的 turnaround 文件，若只有一张直接入库，若有多张弹出选择器或按类型分别入库。
