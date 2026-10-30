## ADDED Requirements

### Requirement: 剧本工作台就地小说正文影视化改编

系统 SHALL 支持从剧本工作台直接发起对指定单集的小说正文影视化改编与受保护契约沉淀。该流程执行时 SHALL 与创意孵化单章流水线保持完全一致的严谨性：
1. 完整传入小说正文文本（不应用 35,000 字代表性采样截断）；
2. 提取并锁定原著金句台词（`ProtectedUtterance`）与核心事实因果（`ProtectedFact`）；
3. 提取结果通过 `StudioProjectManager.importChapterToEpisode` 沉淀至目标集，并自动触发 `mergeMasterAssets` 增量合入可能登场的新角色、新服装形态与新场景卡；
4. 剧本工作台就地捕获完成状态，立即刷新展示最新场次列表与受保护台词数量，无需用户手动刷新或切换页面。

#### Scenario: 剧本工作台就地改编自动沉淀契约与增量资产
- **WHEN** 用户在第 2 集剧本工作台触发小说正文改编并完成
- **THEN** 第 2 集的 `scenes`、`screenplayText` 与 `protectedContract` 均更新为改编结果
- **AND** 本章新登场的配角卡与新场景卡自动增量合并入当前剧集的 IP 资产库，不覆盖已有角色的参考图
