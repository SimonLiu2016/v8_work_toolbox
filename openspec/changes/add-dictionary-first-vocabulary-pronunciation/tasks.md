# Implementation Tasks: add-dictionary-first-vocabulary-pronunciation

## 1. 口音模型与数据结构支持
- [x] 1.1 在 `vocabulary_study_store.dart` 中新增 `VocabularyAccent` 枚举（us 美音 / uk 英音），并在数据模型中持久化 <!-- id: 1.1 -->
- [x] 1.2 在 `VocabularyStudyStore` 中提供口音切换方法 `setAccent` 与 `accent` getter <!-- id: 1.2 -->

## 2. 词典真人发音与本地离线引擎改造
- [x] 2.1 在 `VocabularyStudyStore` 中实现词典真人原声音频下载与缓存逻辑（支持有道/通用词典美音与英音音源） <!-- id: 2.1 -->
- [x] 2.2 确保 `MacOsNativeTtsEngine` 具备美音 `Samantha` 与英音 `Daniel` 的正确调用与音频转码支持 <!-- id: 2.2 -->
- [x] 2.3 在 `VocabularyStudyStore.synthesizeOrGetTtsFile` 中实现三级弹性降级链（词典原声 ➔ macOS 本机语音 ➔ AI TTS 兜底） <!-- id: 2.3 -->

## 3. UI 交互与口音切换支持
- [x] 3.1 在 `VocabularyBrowserDialog` 中增加发音口音切换组件（美音 / 英音），点击即时生效 <!-- id: 3.1 -->
- [x] 3.2 保证 `VocabularyPracticeDialog` 沉浸学习、盲听测验、闪卡自评统一使用当前选定的词典/系统口音发音 <!-- id: 3.2 -->

## 4. 自动化测试与验证
- [x] 4.1 编写单元测试验证词典真人音频下载缓存、离线降级与 AI 终极兜底逻辑 <!-- id: 4.1 -->
- [x] 4.2 编写组件测试验证口音切换对音频请求键与发音播放的影响 <!-- id: 4.2 -->
- [x] 4.3 运行 IT 会议听力训练全套测试确保无功能回归 <!-- id: 4.3 -->

## 5. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 5.1 -->
