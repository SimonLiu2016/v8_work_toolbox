# Implementation Tasks: add-dual-mode-playback-and-shadowing-controls

## 1. 模型与底层控制器扩展
- [x] 1.1 在 `listening_models.dart` 中定义 `ListeningLoopMode` 枚举（`orderOnce`, `listLoop`, `singleLoop`） <!-- id: 1.1 -->
- [x] 1.2 在 `ListeningPlayerController` 中增加 `_loopMode`、`setLoopMode`、`cycleLoopMode` 及对 `_onComplete()` 的分支处理（支持单篇循环与播完停止） <!-- id: 1.2 -->

## 2. 底部控制栏解耦与视觉交互
- [x] 2.1 在 `WorkspacePlayerBar` 中实现篇级播放模式三态按钮（图标随模式改变，Tooltip 清晰说明行为） <!-- id: 2.1 -->
- [x] 2.2 在 `WorkspacePlayerBar` 中提供全场景可见的句级跟读停顿胶囊（`[💬 畅听]` ↔ `[⏸ 逐句跟读]`），支持一键无缝切换与自动恢复连播 <!-- id: 2.2 -->
- [x] 2.3 在 `it_meeting_listening_page.dart` 中对接模式切换的即时反馈提示（Toast） <!-- id: 2.3 -->

## 3. 测试与验证
- [x] 3.1 编写单元测试验证 `cycleLoopMode` 状态流转与单篇循环、播完停止逻辑 <!-- id: 3.1 -->
- [x] 3.2 编写 Widget 测试验证底部控制栏的按钮状态显示与交互触发 <!-- id: 3.2 -->
- [x] 3.3 运行全部听力模块测试确保无回归缺陷 <!-- id: 3.3 -->

## 4. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 4.1 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 4.1 -->
