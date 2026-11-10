## 1. 意群切分与连读弱读规则引擎 (Parser & Highlighter)

- [x] 1.1 在 `transcript_parser.dart` 中实现 `SenseGroupChunker`，支持按标点、从句引导词与从属短语将长句拆分为多行 Chunk 并生成停顿符号
- [x] 1.2 在 `term_highlighter.dart` 中实现连读（Liaison）与弱读功能词（Weak Form）语法识别，支持富文本中连读弧线与浅灰弱化渲染
- [x] 1.3 编写单元测试验证超长复合句的意群切分正确性与高频连读识别准确性

## 2. 播放控制器影子跟读控制 (Player Controller & Hotkeys)

- [x] 2.1 在 `ListeningPlayerController` 中增加单句 A-B 循环控制（`loopingTurnIndex`）与循环边界监听回跳
- [x] 2.2 在 `ListeningPlayerController` 中实现 `toggleQuickSpeed()`（0.8x ↔ 1.0x 极速瞬时切换）与快捷键响应
- [x] 2.3 支持可选的句间自动停顿（Auto-Pause）能力，单句播放完成后留白等待复述
- [x] 2.4 编写控制器测试验证单句死循环回跳与极速变速状态机

## 3. 长难句复盘本服务与模型 (Sentence Vault Store)

- [x] 3.1 定义 `VaultSentence` 数据模型，支持会议来源、发言人、音频切片位置、标签与掌握度状态序列化
- [x] 3.2 实现 `SentenceVaultStore` 服务，负责 `sentence_vault.json` 的原子持久化、增删改查与复习计数统计
- [x] 3.3 编写单测验证难句的持久化落盘与自愈能力

## 4. 界面交互与精听抽屉增强 (UI & UX)

- [x] 4.1 在 `TranscriptDrawer` 顶栏增加视图模式切换：标准视图、意群分块视图、盲听主干遮罩视图
- [x] 4.2 在话轮条目右侧增加“单句循环跟读（🔁）”与“摘录为长难句（⭐）”操作入口，支持弹出标签选择
- [x] 4.3 在底部播放控制栏 `WorkspacePlayerBar` 增加当前单句循环状态指示与极速变速入口
- [x] 4.4 实现「长难句复盘（Sentence Vault）」对话框，支持卡片流盲听翻转、跟读与掌握状态标记

## 5. 验收测试与本地部署验证

- [x] 5.1 运行全量单元测试确保现有会议播放、词汇表与真实会议功能无回归
- [x] 5.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，真实验证长句意群排版、单句影子跟读循环与难句复盘
