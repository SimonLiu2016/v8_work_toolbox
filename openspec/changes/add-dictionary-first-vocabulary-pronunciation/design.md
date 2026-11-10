# Technical Design: add-dictionary-first-vocabulary-pronunciation

## 1. 系统架构与发音调度管道

```
                                  [ 发音播放入口 ]
                (VocabularyBrowserDialog / VocabularyPracticeDialog / 磨耳朵轮播)
                                         │
                                         ▼
                      VocabularyStudyStore.synthesizeOrGetTtsFile
                                         │
                        ┌────────────────┴────────────────┐
                        ▼                                 ▼
                   [ 单个单词 ]                       [ 完整原句 ]
                        │                                 │
                        ▼                                 ▼
             本地 vocab_tts_cache 命中?             商用 AI TTS 模型
                   ├── 是 ──▶ 立即播放              (OpenAiTtsEngine)
                   │
                   ▼ 否
     ┌──────────────────────────────────────────────┐
     │ 1. 词典真人原声 (DictionaryAudioDownloader)  │
     │    • 美音 (type=2) / 英音 (type=1)           │
     │    • 100% 专业外教标准录音                   │
     └──────────────────────┬───────────────────────┘
                            │ 失败 / 无网络 / 404
                            ▼
     ┌──────────────────────────────────────────────┐
     │ 2. macOS 原生离线语音 (MacOsNativeTtsEngine) │
     │    • 美音 (Samantha) / 英音 (Daniel)         │
     │    • say + afconvert 本地直接生成 MP3        │
     └──────────────────────┬───────────────────────┘
                            │ 失败 / 非 macOS
                            ▼
     ┌──────────────────────────────────────────────┐
     │ 3. 商用 AI TTS 模型 (OpenAiTtsEngine)        │
     │    • 终极保底兜底                            │
     └──────────────────────────────────────────────┘
```

## 2. 关键组件与接口设计

### 2.1 口音枚举定义与配置存储
```dart
enum VocabularyAccent {
  us('美音', '美式发音 (US)'),
  uk('英音', '英式发音 (UK)');

  final String label;
  final String description;
  const VocabularyAccent(this.label, this.description);
}
```
在 `VocabularyStudyData` 中增加 `accent` 字段（默认 `VocabularyAccent.us`），支持通过下拉或开关自由切换美音/英音。

### 2.2 词典真人发音下载与缓存
- 有道词典真人发音接口：
  - 美音：`https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=2`
  - 英音：`https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=1`
- 响应内容为 `audio/mpeg`（8~15KB 左右），直接写入 `vocab_tts_cache/dict_${accent.name}_${hash}.mp3`。

### 2.3 macOS 原生离线 TTS 引擎改造
- `MacOsNativeTtsEngine`:
  - 支持传入 `voiceId`：美音使用 `Samantha`，英音使用 `Daniel`；
  - 自动通过 `say -v <voice>` 生成 aiff 并用 `afconvert` 转为 mp3；
  - 执行失败或非 macOS 时抛出异常进入下一级降级。

### 2.4 多级降级容错机制
在 `VocabularyStudyStore.synthesizeOrGetTtsFile` 中：
```dart
Future<File> synthesizeOrGetTtsFile(
  String text, {
  bool forceRegenerate = false,
  VocabularyAccent? accent,
}) async {
  final isSingleWord = !text.trim().contains(' ');
  if (isSingleWord) {
    // 依次尝试：1. 词典真人音频 ➔ 2. macOS 原生离线语音 ➔ 3. AI TTS
    try {
      return await _fetchDictionaryAudio(word, accent: effectiveAccent);
    } catch (_) {
      try {
        return await _synthesizeViaMacNative(word, accent: effectiveAccent);
      } catch (_) {
        return await _synthesizeViaAi(word);
      }
    }
  } else {
    // 原句保留 AI 角色音色合成
    return await _synthesizeViaAi(text);
  }
}
```

## 3. UI 交互体验优化
- 词汇表右上角或控制区增加 **发音口音切换器**（`美音 / 英音` 切换芯片），用户可随时一键切换偏好。
- 练习面板（沉浸学习、盲听测验、闪卡）直接复用当前所选口音发音。
