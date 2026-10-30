# Design: 笔记本与 AI 配置的界面打磨

## Context

见 proposal「背景与问题」。设计层需要知道的现状约束：

**主题串色的机制**。全局 `app_theme.dart:169` 的 `inputDecorationTheme` 是暗色的（`filled: true, fillColor: bgInput=0xFF3C3C3C`）。笔记本是浅色孤岛，`note_editor.dart:467` 用浅色 `Theme` 包裹隔离并覆盖 `filled: false`。但隔离是**逐面板手写**的——新增面板忘了写就串色。本次问答面板与资产面板即因此中招。

**现有组件能力**。`AppTextField`（`app_components.dart:29`）已支持 `obscureText` 与 `suffixIcon`，故密钥字段的眼睛图标无需改组件，只需在调用点加状态与 `suffixIcon`。

**现有弹窗模式**。元数据栏的 `[+ 标签]` 已经是"chip → 弹窗"模式（`note_editor.dart:584` 附近的 `_addTagDialog`），资产/整理/关联三块对齐它即可。

**受影响文件的现状位置**：
- `note_editor.dart:648` 资产面板、`:656` AI 整理按钮、`:667` 关联区 —— 均在工具栏之下
- `asset_fields_panel.dart` —— 自带状态（`_expanded` / `_categoryCtrl` / `_attachments`），通过 `onChanged` 回调外部
- `related_notes_section.dart` —— 自带加载状态与增删逻辑，已拆出 `AiTidyButton`
- `notebook_qa_panel.dart:307` 输入框容器 `0xFFF8FAFC` + 未覆盖 `filled`

## Goals / Non-Goals

**Goals**
- 属性入口在视觉上归属"这篇笔记的属性"，与编辑器画布分离。
- 浅色区域的表单字段可读性由**结构**保证，而非依赖后续新增字段时记得打补丁。
- 密钥可查看，但默认不显示；查看是只读动作。

**Non-Goals**（见 proposal）
- 不改暗色主题、不改功能语义、不改密钥存储格式。

## Decisions

### D1: 抽取共享的浅色边界组件，而非逐字段补 `filled: false`

新增一个轻量包装（如 `NotebookLightScope`），内部即 `Theme(data: ThemeData.light().copyWith(inputDecorationTheme: InputDecorationTheme(filled: false, fillColor: Colors.transparent)))`，笔记本内所有浅色面板一律用它包根节点。

**为什么**：本次遗漏的根因不是"忘了给某个字段加 `filled: false`"，而是**隔离责任落在了每个字段上**。把责任上提到面板边界后，新增字段天然被覆盖。`note_editor` 现有的内联 `Theme` 包裹也改用它，消除重复。

**被否**：逐字段补 `filled: false`（本次就是这样漏的，会再漏）；改全局主题按路由切换深浅（动面太大，且笔记本是页面内的局部浅色区，不是整页主题）。

### D2: 三块属性内容改为"chip → 弹窗"

资产/凭证、AI 整理、关联笔记在元数据栏各占一个紧凑 chip，沿用 `[+ 标签]` 的既有交互。原三块内联区域删除。

**为什么**：资产面板是全功能编辑器（品类 + 4 日期 + 凭证勾选），塞不进一行；而 chip→弹窗既能放进元数据栏，又比内联面板更少占用画布。用户诉求是"位置归属"，不是"必须内联"。

**状态归属**：`AssetFieldsPanel` 现自带 `_expanded`/`_categoryCtrl`/`_attachments` 状态。改为弹窗后 `_expanded` 失去意义（弹窗本身即展开态），`_categoryCtrl` 与 `_attachments` 生命周期收敛到弹窗内。对外仍只需 `onChanged` 回调——**不改其与 `NoteStore` 的交互方式**。

**被否**：内联面板整体上移到元数据栏下方（仍占画布纵向空间，且与"标签"不同排，诉求未满足）；chip 内联展开（实现复杂，收益不明显）。

### D3: 关联笔记 chip 仅在有关联时出现

chip 标签显示计数（`关联 3`），点击弹窗列出关联笔记，支持跳转与移除。无关联时整个 chip 不渲染。

**为什么**：与现有 `RelatedNotesSection` 的"无关联不留占位"语义一致（阶段三已定），且避免元数据栏出现无意义入口。

### D4: 密钥眼睛图标 = 常规切换 + 编辑态空字段时载入已存值

`obscureText` 由状态驱动；`suffixIcon` 放眼睛按钮。编辑已有供应商且字段为空时，首次点击眼睛先 `KeychainService.readSecret(provider.keychainKeyId)` 载入再显示，并给出"已载入已保存的密钥"提示。

**为什么**：`AppTextField` 已支持这两个属性，改动局限在调用点。用户诉求"展示**当前的** key"在编辑态只能靠载入已存值满足——字段本就为空，纯切换看不到东西。

**只读约束**：载入的值仅填入输入框供查看。保存仍按既有逻辑——「留空 = 保持原密钥不变」。若用户载入后未修改，输入框非空会触发一次冗余写入；这是可接受的（值相同，幂等），但如果要严格避免，可在载入时打标记，保存时若值与已存值相同则跳过写入。**倾向后者**，实现成本低且语义更干净。

**被否**：只做常规切换（编辑态点了没反应，不满足诉求）；眼睛直接展示只读文本而不填输入框（用户无法复制/修改，体验割裂）。

### D5: 不引入"显示密钥"的全局偏好

不提供"总是显示密钥"的设置项。

**为什么**：密钥是敏感值，默认遮蔽 + 显式动作是安全默认；全局偏好会让用户在一次设置后长期暴露密钥。与既有 `secure-secret-storage` 的谨慎取向一致。

## Risks / Trade-offs

**[chip 承载不了资产摘要信息]** → 资产 chip 若只显示"资产"两字，用户看不出这条笔记有没有资产数据、快到期没。
缓解：有资产数据时 chip 显示品类或到期倒计时（如 `资产·延保服务` / `资产·1200天`），无数据时显示裸 `资产`。

**[弹窗比内联多一次点击]** → 记录资产需要点 chip 再编辑，比内联面板多一步。
缓解：接受。资产登记是低频动作，而编辑器画布空间是高频诉求。

**[载入密钥到输入框带来冗余写入]** → 见 D4。
缓解：载入时记录值与来源，保存时若与已存值相同则跳过写入。

**[浅色边界组件被漏用]** → 新增面板仍可能忘记包它。
缓解：组件命名明确（`NotebookLightScope`）+ 文档注释说明"笔记本内浅色面板必须包此边界"；spec 已有「Newly added light-surface panel inherits isolation」场景，review 时可据此拦截。

## Migration Plan

三组改动相互独立，可分别交付与验证：

1. **主题隔离**（D1）—— 先做，它独立且修复的是可读性 bug（影响当前使用）。
2. **元数据栏收拢**（D2/D3）—— 触及布局与组件形态，改动最大，单独一步。
3. **密钥可见性**（D4/D5）—— 独立文件（`ai_config_page.dart`），与笔记本无耦合。

**回滚**：各组独立，回滚任一组不影响其他。无声明的数据迁移（不动 schema、不动存储格式）。

## Open Questions

无。用户已定：单一 change 三组任务；问题 3 采用"常规切换 + 编辑态载入已存值"折中；关联笔记一并挪入元数据栏。
