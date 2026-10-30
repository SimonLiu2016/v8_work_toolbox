## Why

「听力练习 → 词汇表」的连播（连续磨耳朵）播放按钮一点即报错，连播条下方出现红色文案：

```
发音失败：type '() => Null' is not a subtype of type ...
```

该文案由 `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart:326` 的 `catch` 拼出，但它只暴露 `$e.toString()`——既不打印堆栈，也不落地到 AI 调用日志（实测 `logs/ai.log` 对出错的那一次**零痕迹**），因此**知道它炸了，却不知道炸在哪一行**。更深的问题是：这条播放链路在测试里**永远被注入的假播放器（`audioPlayerFn`）短路**，生产环境唯一走的真实 `AudioPlayer` 分支从未被任何测试执行过——崩溃既解释不清，也防不住回归。

## What Changes

- **修复**「词汇表」发音播放的运行时崩溃。三条入口共享同一套播放实现，需一并覆盖：
  - 单词发音（单词助学头卡 🔊）
  - 句子发音（原句出处卡 🔊）
  - 连续磨耳朵（连播条 ▶，即本次报错入口）
- **诊断先行**：捕获到的异常必须连同**异常类型、消息、堆栈**一起暴露（写日志 + UI 给可读摘要），使下一次复现能直接定位抛错行；不再只留一句笼统文案。
- **关闭覆盖盲区**：把「真实播放器分支」纳入自动化测试。现状是测试全部注入 `audioPlayerFn`，导致生产分支与测试分支不是同一段代码——这是本 bug 能长期存活的直接原因（与此前记过的「mock 只 mock 一半」同类）。
- **明确失败语义**：单个词发音失败**不中断**连续播放（维持现状行为），但用户与日志都必须能看出「哪一个词失败了、为什么」。
- **不改变**：不引入新的播放器依赖；不改动 TTS 合成（`OpenAiTtsEngine`）与供应商解析链路——实测该链路正常（连播那批词全部 HTTP 200、日志 0 条 `[ERROR]`），故障发生在**合成之后的播放段**。

## Capabilities

### New Capabilities

（无。词汇表发音播放属于既有「IT 会议听力工具」能力的组成部分，不新开 capability。）

### Modified Capabilities

- `it-meeting-listening-tool`: 新增需求——「词汇表发音播放」的失败必须可定位（暴露底层异常类型与堆栈摘要，并落地日志），且该播放链路必须存在覆盖**真实播放器分支**的可自动化验证；连播中单词级失败不得中断连播。

## Impact

**受影响代码**

- `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart` — 播放实现（`_playTts` / `_playWordTtsAndWait` / `_playWordAtContinuousIndex` / `_startContinuousPlayback`）与红色错误文案渲染；本次崩溃的 catch 点。
- `test/it_meeting_listening/vocabulary_player_and_transcript_scroll_test.dart` — 现全部用例注入 `audioPlayerFn`，需补上不注入（真实分支）的覆盖。
- `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart` — `synthesizeOrGetTtsFile` 的缓存命中/合成两条路径（已确认非故障点，但需在测试中固定其行为）。

**不受影响**

- `lib/tools/reader/services/tts_engine.dart`（TTS 合成引擎）与 `lib/services/ai_config_store.dart`（TTS 槽位解析）：已验证类型干净、日志显示合成本身成功。
- 词汇表的数据模型、重点关注、句子翻译等非播放功能。

**诊断依据（本次排查已确证，供实现阶段直接使用）**

- 报错文本与红色渲染点全仓各仅一处，渲染位置就在连播条正下方 → 触发入口＝连播条 ▶ 按钮，catch 点＝`vocabulary_browser_dialog.dart:326`。
- `() => Null` 是 Dart VM 对「**没有函数类型上下文的零参闭包**」的运行时类型打印名（`() {}` 与 `() => null` 在宽槽位下都是 `() => Null`）。要抛出该错误，闭包必须先被塞进 `Function` / `dynamic` / `Map` 这类宽槽位，之后又被当作**带必填参数或非空返回**的具体函数类型使用。
- `analysis_options.yaml` 仅 include `flutter_lints`，**未开启 `strict-casts`**，故此类隐式降级编译期静默放行——本项目需按此假设排查。
- 全量 strict-casts 扫描（临时开启后已还原）结论：`lib/` 内**不存在**任何"隐式降级到函数类型"的点；`audioplayers` 6.7.1、`audioplayers_platform_interface` 7.1.1、`flutter_secure_storage` 9.2.4 **全包无裸 `Function`**。
- 已实测排除：`Future<void>.timeout(4s, onTimeout: () {})` 的超时路径无害（`vocabulary_browser_dialog.dart:359-362`）。
- 尚缺的关键信息：报错尾部 `is not a subtype of type '...'` 中的**目标类型名**，以及**抛错行号**——这正是「诊断先行」要先补上的东西。