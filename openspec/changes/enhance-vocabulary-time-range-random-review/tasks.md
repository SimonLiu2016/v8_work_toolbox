# Implementation Tasks: enhance-vocabulary-time-range-random-review

## 1. 学习记录时间戳与时间范围筛选引擎
- [x] 1.1 在 `vocabulary_study_store.dart` 中声明 `ReviewTimeRange` 枚举并实现 `getWordsStudiedInRange` 接口 <!-- id: 1.1 -->
- [x] 1.2 在 `VocabularyStudyStore` 中实现 `recordWordStudied(word)`，并在沉浸学习翻阅时同步记录时间戳 <!-- id: 1.2 -->

## 2. 复习定制弹窗 UI 与交互
- [x] 2.1 创建 `VocabularyReviewDialog`，实现 5 档时间范围选择、动态词数统计、模式切换与随机乱序开关 <!-- id: 2.1 -->
- [x] 2.2 在 `VocabularyBrowserDialog` 中将「复习今日」升级为「复习」，点击弹出定制面板并根据配置启动乱序复习 <!-- id: 2.2 -->

## 3. 自动化测试与验证
- [x] 3.1 编写单元测试验证各时间跨度的已学单词筛选、时间戳记录与随机洗牌出题 <!-- id: 3.1 -->
- [x] 3.2 编写组件测试验证复习弹窗交互、词数动态更新、随机乱序出题与零词禁用状态 <!-- id: 3.2 -->
- [x] 3.3 运行全量测试套件确保无回归 <!-- id: 3.3 -->

## 4. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 4.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 4.1 -->
