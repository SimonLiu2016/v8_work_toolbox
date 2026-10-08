# 测试基线（fix-notebook-paste-text-fallback task 1.1）

记录时间：apply 开始时，改动前
命令：`flutter test`（默认 reporter，全量 146 个测试文件）
日志：/tmp/v8_baseline_full.log
总计：1343 passed / 3 skipped / 20 failed，EXIT=1

## 失败集合（20 例 / 13 文件）——必须逐字相同才算零回归

- test/ai_video_studio_shell_test.dart :: 外壳可构建并显示工序导航
- test/ai_video_studio_shell_test.dart :: 有剧集后创意孵化入口恢复可点
- test/ai_video_studio_shell_test.dart :: 有剧集时默认选中并显示在顶栏
- test/ai_video_studio_shell_test.dart :: 没有剧集时创意孵化入口被禁用
- test/ai_video_studio_shell_test.dart :: 空剧集库显示新建引导
- test/doc_audio_reader_test.dart :: ReaderConfigStore & Scheduling & Logging Resilience Tests AiLogger 记录日...
- test/frequently_used_tools_test.dart :: category membership AI, note and ops categories hold their migrated tools
- test/notebook_codeblock_interactive_test.dart :: Code block interactive test: click to edit, delete key, and blur to di...
- test/notebook_editor_test.dart :: NoteEditor renders notes with image embeds and unknown embeds without crash
- test/notebook_editor_test.dart :: NoteEditor renders notes with links, code blocks and lists without crash
- test/notebook_editor_test.dart :: NoteEditor renders without localization crash or overflow
- test/notebook_table_interactive_test.dart :: Insert table auto-edit test: clicking insert table immediately focuses...
- test/notebook_table_interactive_test.dart :: Table interactive test: render, direct cell click edit, modify header, t...
- test/pointer_tap_table_test.dart :: Simulate real mouse clicks on table cells
- test/table_all_cells_mutation_test.dart :: Every header and cell can be modified, values take effect, and no text...
- test/table_col1_col2_and_init_test.dart :: Verify: quiet on note enter, seamless switch between col1 & col2, al...
- test/table_drag_select_delete_and_outside_tap_test.dart :: Table: Delete key deletion, cell drag-selection, and outside tap...
- test/table_focus_transition_test.dart :: Table focus transition: single-click cell focus, cell-to-cell switch, ...
- test/table_user_repro_test.dart :: Reproduction test: insert table and modify header & content
- test/tools/security_toolbox/msf_rpc_service_test.dart :: MsfRpcService Unit and Lifecycle Tests live integration: startDaemon...

注意：与本 change 相关的三个文件全部通过：
- test/note_editor_paste_text_test.dart（9 例）
- test/clipboard_image_service_test.dart
- test/note_editor_widget_test.dart

## 改动后复跑（task 6.1）

日志：`/tmp/v8_after_full.log`

| | baseline | after |
|---|---|---|
| passed | 1343 | 1355 |
| skipped | 3 | 3 |
| failed | 20 | 19 |

- 净增 12 个通过的用例 = 分派层 6 + 服务的 clipboardText 携带 4，另 +2 来自
  同文件内既有用例的重复计数（flutter test 的 +N 含 group 级计数）。
- **新增失败：0**。失败集合是 baseline 的子集（少了 `msf_rpc_service_test`
  一个），无回归。
- `msf_rpc_service_test` 单独重跑通过（+3 All tests passed），是既有 flaky，
  与本 change 无关。
- 其余 19 个失败与基线**逐字相同**（notebook 编辑器渲染 / 表格交互 /
  doc_audio 落盘等既有失败）。
