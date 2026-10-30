## 1. 批量整理核心服务 (BatchOrganizerService)

- [x] 1.1 定义 `BatchOrganizeProgress`、`BatchOrganizeSummary`、`BatchOrganizeScope` 数据模型及取消控制信号
- [x] 1.2 实现 `BatchOrganizerService` 调度主循环，遍历目标笔记、跳过空白/极短笔记并串行调用 `NotebookKbService`
- [x] 1.3 实现自动化安全落库逻辑：标签合并去重落库及关联边写入（过滤自环与重复关联）
- [x] 1.4 实现单篇异常容错捕获与记录，保证批量执行不因个别超时或异常中断

## 2. 知识星图交互与嵌入式进度条 (KnowledgeGraphView)

- [x] 2.1 在 `KnowledgeGraphView` 顶部 Header 增加「批量AI整理」按钮
- [x] 2.2 实现启动准备对话框，展示有效笔记数与未关联笔记数，提供「全部笔记」与「仅未关联笔记」范围选择
- [x] 2.3 在 Header 实现嵌入式非阻塞进度栏：包含进度文本（当前/总数及当前标题）、`LinearProgressIndicator` 和「停止」按钮
- [x] 2.4 实现执行完成与用户主动停止后的汇总报告 SnackBar 提示与星图数据自动重新加载

## 3. 自动化测试验证

- [x] 3.1 编写 `test/notebook_batch_organizer_test.dart` 测试用例，验证范围过滤、自动落库、去重保护与取消机制
- [x] 3.2 运行所有笔记本相关测试确保零回归

## 4. 应用构建与本机部署

- [x] 4.1 编译打包 macOS Release 版本 (`flutter build macos --release`)
- [x] 4.2 覆盖替换本机应用 `/Applications/V8WorkToolbox.app` 并启动验证
