## 1. 底层 JSON 解析器数组截断自愈容错 (AiConstraintEngine)

- [x] 1.1 在 `AiConstraintEngine.parseJsonLoose` 中实现未闭合数组与截断残片的安全修补算法（扫描最后一个完整对象的闭合大括号 `}` 并安全闭合 `]}`）
- [x] 1.2 编写单元测试验证截断修复能力，确保即便大模型输出被强行中断，也能 100% 抢救出截断前已完整输出的分集数据

## 2. 两阶段按大幕分批推演管线 (AiConstraintEngine)

- [x] 2.1 新增全季宏观大幕规划任务与轻量 Prompt，确保以极低 Token 消耗（~400 Tokens）稳定产出四幕弧光与集数跨度
- [x] 2.2 重构 `AiConstraintEngine.planWritersRoomSeasonBeats`：当目标集数大于 20 集时自动触发两阶段管线，按大幕范围分批推演具体分集（每批 12~16 集）并按序聚合
- [x] 2.3 支持 `onProgress` 阶段进度通知，并在跨幕推演时向前传递上一幕的高潮转折作为衔接上下文

## 3. 编剧研讨室界面分阶段流式进度与体验 (WritersRoomDialog)

- [x] 3.1 在 `WritersRoomDialog` 中接入 `onProgress` 回调，实时展示大幕规划与各篇章分集推演进度
- [x] 3.2 优化重试机制中的 `retryHint` 处理，杜绝将数千 Token 的截断残片回灌到重试请求中

## 4. 自动化测试与本地应用部署

- [x] 4.1 编写并运行单元测试与静态分析，验证大集数分段推演、截断自愈与无缝合并全量大纲
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，端到端验证 60 集小说全季大纲规划流畅完成
