# Implementation Tasks: add-adaptive-auditory-familiarity-review

## 1. 熟悉度模型与记忆存储升级
- [x] 1.1 在 `vocabulary_study_store.dart` 中声明 `AuditoryFamiliarity` 枚举与 `evaluateFamiliarity` 判定逻辑 <!-- id: 1.1 -->
- [x] 1.2 扩展 `VocabularyStudyStore.recordQuizResult` 支持 `playCount` 与 `responseDuration`，按熟悉度动态调整熟练度与复习排期 <!-- id: 1.2 -->

## 2. 会话引擎与行为遥测
- [x] 2.1 在 `PracticeItem` 中扩展 `playCount`、`displayedAt`、`familiarity` 与 `isReinforcement` 字段 <!-- id: 2.1 -->
- [x] 2.2 在 `VocabularySessionController` 中实现听音计数 `recordPlay()`、耗时计算及会话内生疏词追加强化队列机制 <!-- id: 2.2 -->

## 3. UI 交互与反馈呈现
- [x] 3.1 在 `VocabularyPracticeDialog` 中打通听音次数累加（含自动播放、点击与空格键）与精确作答计时 <!-- id: 3.1 -->
- [x] 3.2 在盲听测验作答后卡片区域呈现听觉熟悉度诊断微章与排期/强化提示 <!-- id: 3.2 -->

## 4. 自动化测试与验证
- [x] 4.1 编写单元测试覆盖不同播放次数与耗时对应的熟悉度评定与排期动态缩短/延长 <!-- id: 4.1 -->
- [x] 4.2 编写组件测试验证盲听测验行为遥测、熟悉度诊断微章及末尾回捞重测流转 <!-- id: 4.2 -->
- [x] 4.3 运行重点词汇与听力练习全套测试套件确保无回归 <!-- id: 4.3 -->

## 5. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 5.1 -->
