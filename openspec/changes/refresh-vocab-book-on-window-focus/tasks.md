## 1. 聚焦刷新

- [x] 1.1 `VocabBookPage` 挂窗口焦点监听。注意 `WindowListener` 在 window_manager 0.5.x 是**抽象类**不是 mixin，State 无法 `with`；用只覆写 `onWindowFocus` 的薄壳 `_WindowFocusRelay` 转接，`initState` add / `dispose` remove
- [x] 1.2 `_onWindowFocus()` 里重新查询词库。走全量查询而非按筛选重查：拿全量后 `_filteredEntries` 会按当前筛选重新过滤，结果等价，且不会把用户已应用的筛选冲掉
- [x] 1.3 查完比对（`vocabListChanged` / `vocabEntrySignature`），有变化才 `setState`；标签集合变了也要算变化（筛选栏的计数来自它）
- [x] 1.4 选中项按 id 跟踪，刷新后仍在同一条上（它可能刚被别处改过）
- [x] 1.5 守卫：`_isLoading` 时聚焦直接返回，不并发再起一次
- [x] 1.6 `_loadData(silent: true)`：不碰 `_isLoading`、不清空列表 —— 刷新必须静默

## 2. 测试与验证

- [x] 2.1 单测（`test/vocab_refresh_diff_test.dart`，16 例全过）：新增/删除/顺序/id 变化、**纯 mastery 与纯 tag 变更**、definitions 空→非空、以及**反向**守卫——第二条释义追加与 examples-only 变更**不算**变化（不在列表里， rebuilt 就是白闪）
- [x] 2.2 筛选态保持由结构保证，不需要单独单测：刷新走全量查询填 `_entries`，`_filteredEntries`（第 174 行的 getter）按 `_selectedMastery` / `_selectedTag` / `_searchQuery` 重新过滤。筛选条件在刷新路径里**根本没有被赋值**，不可能掉。task 原文写的"按筛选重查"是更弱的实现——已按 1.2 的全量查询方案落地，这条随之失效
- [x] 2.3 运行 `flutter analyze` 与全量测试，确认零回归——`flutter analyze lib/` 零 error；全量 `+1034 ~3 -13`，失败集合与改动前**逐字相同**（diff 为空），通过数 +16（新增的比对用例）
- [ ] 2.4 实机：浏览器浮窗加词 → 切回主窗口 → 生词本页出现新词条，且无闪烁、滚动位置不变
- [ ] 2.5 实机：不加任何词，反复切换窗口焦点 → 列表不闪、选中不丢、筛选不掉

## 3. 部署

- [ ] 3.1 运行 `./scripts/deploy_local.sh` 并重新启动应用
- [ ] 3.2 核对新构建 AOT 快照已变化、strict 签名校验通过
- [ ] 3.3 若与 `fix-browser-lookup-ai-and-vocab-flow` 同期部署，浏览器侧需重载扩展
