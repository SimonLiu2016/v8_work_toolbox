## 1. 拼段边界判据修正

- [x] 1.1 `prompt_assembler.dart` 的 `_joinSegments` 判据从「前一段含换行」改为「前一段或本段含换行」
- [x] 1.2 跑 `test/ai_video_studio_prompt_assembler_test.dart`、`test/agnes_studio_pipeline_test.dart` 等五个提示词相关测试文件，确认负向词恢复逗号分隔、无新增失败

## 2. 遗留断言同步

- [x] 2.1 `test/ai_video_studio_prompt_assembler_test.dart` 的「剥离对白台词与剧本标头」改名为「对白保留为时间区间内的配音行，剧本标头被剥离，锁定主物理场景，机位协调」
- [x] 2.2 该测试的台词断言从「不含台词原文」改为「含 `对白：<原文>`」；动作断言从逗号平接改为 `动作：<原文>` 分行存在；补「声音与画面约束」存在断言
- [x] 2.3 全量 `flutter test` 确认无新增失败
- [x] 2.4 `openspec validate fix-prompt-segment-join-and-dialogue-retention --strict` 通过
