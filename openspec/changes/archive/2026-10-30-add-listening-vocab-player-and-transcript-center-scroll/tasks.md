## 1. 词汇表单行发音与连续朗读播放器开发

- [x] 1.1 在 `VocabularyBrowserDialog`（`lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`）单词行 `_entryTile` 中常驻单行发音按钮，支持未展开状态下直接点听单词发音
- [x] 1.2 在 `VocabularyBrowserDialog` 顶部引入列表连续播放控制栏，支持对当前视图单词执行顺序朗读、暂停、上一词、下一词、循环开关与进度指示（如 `5/24`）
- [x] 1.3 实现连续朗读调度状态机，支持单词读完后保持 1.5 秒停顿缓冲、自动步进下一词、当前朗读词高亮态展示与视窗平滑居中跟随

## 2. 精听文稿视图重构与居中对齐滚动控制

- [x] 2.1 将 `TranscriptDrawer`（`lib/tools/it_meeting_listening/ui/transcript_drawer.dart`）重构为 `StatefulWidget`，引入 `ScrollController` 与每轮句项对齐索引
- [x] 2.2 实现初次展开与窗口重新打开时的强制居中对齐机制（`alignment: 0.5`），确保正在播放的句子在打开瞬间立即可见并位于视窗正中央
- [x] 2.3 实现音频播放中句子过渡时的平滑滚动跟随，以及用户手动翻阅检测与右下角「⬇ 回到正在朗读句」悬浮按钮交互

## 3. 验证与本地部署

- [x] 3.1 编写单元与组件测试覆盖词汇表单行点听、列表连续朗读步进与文稿抽屉居中滚动定位（`test/it_meeting_listening/`）
- [x] 3.2 运行 `flutter analyze` 确保目标代码零错误、零警告
- [x] 3.3 运行 `openspec validate add-listening-vocab-player-and-transcript-center-scroll --strict` 确保规范严格合规
- [x] 3.4 执行 `./scripts/deploy_local.sh` 重新构建并替换本机 `/Applications/V8WorkToolbox.app`
