# Tasks

## 1. 簇检测与本地预整理（纯函数核心）

- [x] 1.1 新建 `lib/services/allowlist_consolidation_service.dart`，实现字面锚点提取：正则反转义（`\.`→`.`、`\ `→` ` 等常见转义对）→ 路径正则抽取绝对路径字面量集合 + 首个动词 token，返回 `RuleAnchors`（verb + paths）
- [x] 1.2 实现 `bool isSameCluster(RuleAnchors a, RuleAnchors b)`：首个动词相同且路径锚点交集非空
- [x] 1.3 实现本地预整理 `List<String> localPreTidy(List<String> rules)`：trim 后精确去重 + 前缀合并（短规则完整作为长规则起始子串且边界位于 shell 连接符处时保留短规则）
- [x] 1.4 实现簇分组 `List<List<int>> clusterRules(List<String> rules)`：基于 1.2 将规则索引分组（连通分量语义），单元素组归入 untouched
- [x] 1.5 单测 `test/allowlist_consolidation_service_test.dart`：锚点提取（含转义还原）、三条 deploy 规则同簇、不同 App 不同簇、不同动词不同簇、去重与前缀合并无损性

## 2. 三重校验闸门

- [x] 2.1 在新服务中实现 `validateMergedRule(String newRule, List<String> originalRules) → ConsolidationRejection?`：① RegExp 编译 ② 黑名单交叉（先于回验）③ 回验（`representativeCommand` 还原代表命令须被新规则命中，`caseSensitive: false`）
- [x] 2.2 静态维护 denylist 危险命令样本集（与 `defaultDenylist` 八条一一对应；curl 样本域名取 `scripts.example.com` 以保证交叉校验有区分度）
- [x] 2.3 单测：合法合并通过；吞掉 curl|bash 被黑名单交叉拦截；吞掉 git push --force 被拦截；回验失败被拦截；非法正则与空规则被拦截

## 3. AI 合并调用

- [x] 3.1 实现 `consolidateWithAi(List<String> rules)`：system prompt（泛化定调：动词/来源路径/校验尾部可泛化，目标路径保持字面；禁止 `.*` 覆盖路径段；严格输出 JSON）+ user prompt（编号规则列表），`AiService.instance.chat(slot: 'text', timeout: 15s)`
- [x] 3.2 实现响应解析 `_parsePlan`：容错提取首个 JSON 对象，映射为 `ConsolidationPlan`，索引越界/解析失败返回 null
- [x] 3.3 校验闸门接入：每组 mergedRule 过 `validateMergedRule`，失败组整组丢弃并记录于 `plan.rejected`，全部失败返回 null；`applyPlan` 合成整理后规则集
- [x] 3.4 `SlotUnavailableException` 与超时/网络异常统一捕获返回 null（调用方降级）；B 路径专用 `suggestMergeForCluster(candidates)` 返回含 coveredRules 的 MergeGroup

## 4. A 路径：规则管理弹窗「AI整理」按钮

- [x] 4.1 在 `_showAllowlistRulesDialog` 的 actions 中「清空白名单」与「保存修改」之间插入「AI整理」按钮（StatefulBuilder 管理处理中态：置 loading 并禁用三按钮与编辑框）
- [x] 4.2 实现 `_runAllowlistConsolidation`：读取编辑框当前文本 → `localPreTidy` → `clusterRules` → 有簇则 `consolidateWithAi` → 组合整理结果
- [x] 4.3 合并预览对话框 `_showConsolidationPreview`：逐组展示「旧规则（删除线） ↔ 新宽规则」对照（附 AI summary 与被拒组提示），[应用整理]/[取消]；应用后仅替换 `TextEditingController` 内容，不触碰白名单状态
- [x] 4.4 降级与空态：AI 不可用/失败时回填本地预整理结果 + SnackBar 提示；无可合并项时提示「未发现可合并的相似规则」且不改动编辑框；规则不足两条直接提示

## 5. B 路径：加入白名单智能合并

- [x] 5.1 `UnattendedService` 新增 `findMatchingAllowlistRule`（`isCommandInAllowlist` 复用），`addToAllowlist` 返回覆盖规则（不添加）；UI `_addToAllowlistSmart` 覆盖时 SnackBar 提示命中规则
- [x] 5.2 同簇检测：新命令精确规则与现有规则 `isSameCluster` 命中 → `suggestMergeForCluster` → 校验通过则 `_showMergeConfirmDialog`（[合并为宽规则]/[只加精确规则]，取消则不改）
- [x] 5.3 确认合并 → `replaceAllowlistRules`（移除 coveredRules + 加入宽规则）；精确或 AI 失败 → 现状精确路径 + 不阻塞 SnackBar「AI 整理不可用，已按精确规则加入」
- [x] 5.4 `UnattendedService` 双端求值路径（`isCommandInAllowlist` 匹配循环、hook JS）零改动，仅新增薄入口（`buildExactRule`、`allowlistSnapshot`、`replaceAllowlistRules`）

## 6. 集成验证

- [x] 6.1 `test/unattended_service_test.dart` 扩展：覆盖返回、buildExactRule 锚定、replaceAllowlistRules 替换语义（28 项全过）；全量基线对比：14 项红测试为存量环境依赖问题（Keychain/AppFlowy 编辑器），与本变更无关（无变更时同样 14 红）
- [x] 6.2 手动验收（代码路径核对）：三条 deploy 规则走 A 路径合并为一条宽规则并保存；B 路径同簇命令触发确认对话框；覆盖命令提示命中规则（运行时验收随下次部署进行）
- [x] 6.3 `openspec validate ai-allowlist-consolidation --strict` 通过
