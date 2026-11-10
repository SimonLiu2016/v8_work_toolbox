# Implementation Tasks: fix-vocabulary-practice-issues-and-progress

## 1. 练习进度持久化存储扩展
- [x] 1.1 在 `VocabularyStudyData` 与 `VocabularyStudyStore` 中实现 `practiceProgress` 字段与 JSON 序列化 <!-- id: 1.1 -->
- [x] 1.2 在 `VocabularyStudyStore` 中提供保存进度 `savePracticeProgress`、获取进度 `getPracticeProgress` 及重置进度 `clearPracticeProgress` 接口 <!-- id: 1.2 -->

## 2. 会话引擎支持断点接续与重置
- [x] 2.1 扩展 `VocabularySessionController.create`，支持传入 `initialWord` 自动定位初始题目索引 <!-- id: 2.1 -->
- [x] 2.2 在 `VocabularySessionController` 中实现 `resetToBeginning()` 支持从头开始重置 <!-- id: 2.2 -->

## 3. UI 修复与交互改进
- [x] 3.1 替换所有模式中的 `IconButton.filledTonal` 为显式高对比度圆形徽标按钮，确保常态可见与动效明确 <!-- id: 3.1 -->
- [x] 3.2 修复 `_buildQuizOptionTile` 字重逻辑，未作答前 4 项统一为普通字重，作答后方呈现对错加粗 <!-- id: 3.2 -->
- [x] 3.3 在 `VocabularyPracticeDialog` 顶部增加断点续学提示及 `[↺ 从头开始]` 按钮，联动实时保存与结算重置 <!-- id: 3.3 -->

## 4. 自动化测试与验证
- [x] 4.1 编写单元测试覆盖练习进度的持久化存取与会话引擎断点定位 <!-- id: 4.1 -->
- [x] 4.2 编写组件测试验证盲听测验未作答选项字重无泄题与从头开始交互 <!-- id: 4.2 -->
- [x] 4.3 运行重点词汇与听力练习测试套件确保无回归 <!-- id: 4.3 -->

## 5. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 5.1 -->
