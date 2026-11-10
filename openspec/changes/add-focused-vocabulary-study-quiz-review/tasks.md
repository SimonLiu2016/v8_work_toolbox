# Implementation Tasks: add-focused-vocabulary-study-quiz-review

## 1. 记忆状态模型与存储扩展
- [x] 1.1 在 `vocabulary_study_store.dart` 中实现 `WordMemoryState` 与记忆曲线更新算法 <!-- id: 1.1 -->
- [x] 1.2 扩展 `VocabularyStudyData` 与 `VocabularyStudyStore`，支持向后兼容反序列化与记忆状态持久化 <!-- id: 1.2 -->
- [x] 1.3 在 `VocabularyStudyStore` 中提供今日待复习、易错词、已掌握词的筛选接口 <!-- id: 1.3 -->

## 2. 学习考核与练习会话引擎
- [x] 2.1 实现 `VocabularySessionController`，封装题目队列、4 选 1 干扰项生成、进度流转与统计 <!-- id: 2.1 -->
- [x] 2.2 实现沉浸刷词（Study）、盲听 4 选 1（Quiz）、闪卡翻牌自评（Flashcards）三种会话类型的数据驱动逻辑 <!-- id: 2.2 -->

## 3. UI 交互实现与词汇表无缝接入
- [x] 3.1 创建沉浸式练习面板 `VocabularyPracticeDialog`，实现刷词卡、4 选 1 测验卡、闪卡翻牌与答题结算卡 <!-- id: 3.1 -->
- [x] 3.2 支持快捷键操作（空格发音、数字键 1~4 作答/自评、Enter/箭头下一步、Esc 退出） <!-- id: 3.2 -->
- [x] 3.3 在 `VocabularyBrowserDialog` 重点关注页中集成状态筛选微章与四个模式入口 <!-- id: 3.3 -->

## 4. 自动化测试与验证
- [x] 4.1 编写单元测试验证记忆状态机与 SM-2 间隔更新算法 <!-- id: 4.1 -->
- [x] 4.2 编写组件测试验证练习面板在 4 选 1 测验与闪卡自评中的正确流转与数据记录 <!-- id: 4.2 -->
- [x] 4.3 运行全部测试确保无回归 <!-- id: 4.3 -->

## 5. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 5.1 -->
