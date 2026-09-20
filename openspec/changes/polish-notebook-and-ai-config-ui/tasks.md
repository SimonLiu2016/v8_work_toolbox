# Tasks: 笔记本与 AI 配置的界面打磨

> 三组独立改动，按依赖与影响排序：先修可读性 bug（组 1），再做布局收拢（组 2），
> 最后密钥可见性（组 3，独立文件）。

## 1. 浅色面板主题隔离（修复可读性）

- [x] 1.1 新建共享浅色边界组件（如 `lib/tools/notebook/ui/notebook_light_scope.dart`）：内部 `Theme(data: ThemeData.light().copyWith(inputDecorationTheme: InputDecorationTheme(filled: false, fillColor: Colors.transparent)))`；类文档注释说明"笔记本内浅色面板必须包此边界，新增字段不得依赖逐个覆盖 filled"
- [x] 1.2 `notebook_editor.dart` 现有的内联浅色 `Theme` 包裹改用该组件，消除重复
- [x] 1.3 `notebook_qa_panel.dart` 用该组件包裹根节点（修复输入框深灰填充盖住浅底、文字不可读）
- [x] 1.4 资产面板/弹窗用该组件包裹，修复「品类」输入框同类缺陷
- [x] 1.5 复核笔记本内其余浅色容器（关联区、AI 建议弹窗、标签弹窗）是否也需包裹
- [ ] 1.6 手工验证：问答面板输入框文字清晰；资产弹窗品类输入框文字清晰

## 2. 元数据栏收拢属性入口

- [x] 2.1 `asset_fields_panel.dart` 改造为弹窗形态（如 `showAssetDialog`）：保留品类/购买日/服务期/到期日/凭证勾选全部功能，去掉不再需要的 `_expanded` 折叠态，状态收敛到弹窗内，对外仍只走 `onChanged`
- [x] 2.2 新增元数据栏的资产 chip：无资产数据时显示裸「资产」，有数据时显示品类或到期倒计时（如 `资产·延保服务` / `资产·1200天`）
- [x] 2.3 元数据栏加入「AI 整理建议」chip，接入现有 `AiSuggestionDialog`
- [x] 2.4 关联笔记改为 chip：显示计数（`关联 N`），点击弹窗列出关联笔记，支持跳转与移除；**无关联时不渲染该 chip**
- [x] 2.5 删除 `note_editor.dart` 中工具栏之下的三块内联区域（资产面板 / AI 整理按钮行 / 关联区）
- [x] 2.6 `related_notes_section.dart` 调整为弹窗内容形态（保留跳转 `onOpenNote` 与移除逻辑）；`AiTidyButton` 若不再被使用则删除
- [ ] 2.7 确认编辑器画布不再被属性块压缩：格式工具栏紧邻画布，画布占据剩余全部纵向空间
- [ ] 2.8 手工验证：同时有标签、资产、关联的笔记，元数据栏四个入口齐全，画布未被挤压

## 3. API Key 遮蔽与查看

- [x] 3.1 `ai_config_page.dart` 供应商对话新增 `_keyVisible` 状态；`AppTextField(obscureText: !_keyVisible)`，`suffixIcon` 放眼睛按钮（`visibility` / `visibility_off`）
- [x] 3.2 编辑已有供应商且字段为空时，首次点击眼睛从 `KeychainService.readSecret(provider.keychainKeyId)` 载入已存密钥再显示，并提示「已载入已保存的密钥」
- [x] 3.3 载入失败（读不到）时明确提示无法载入，而非静默显示空字段
- [x] 3.4 避免冗余写入：载入时记录来源值，保存时若输入框值与已存值相同则跳过 `writeSecret`
- [x] 3.5 新建供应商时不触发载入逻辑（无已存密钥）
- [ ] 3.6 手工验证：新建时输入即星号、点眼睛可核对明文；编辑时点眼睛能看到已存密钥；不改动直接保存不产生冗余写入

## 4. 验证与收尾

- [x] 4.1 全量回归：`flutter test`，确认无新增失败
- [x] 4.2 构建部署：`flutter clean` → `flutter build macos --release` → `codesign -v --strict` 通过 → 替换 `/Applications` → 校验 AOT 快照哈希 → 启动采样 stderr 无未捕获异常
- [ ] 4.3 实机验证三项成功判据：元数据栏四入口齐全且画布不被挤压；问答输入框可读；编辑态可查看已存密钥
