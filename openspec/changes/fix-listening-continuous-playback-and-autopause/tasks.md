# Implementation Tasks: fix-listening-continuous-playback-and-autopause

## 1. 控制器状态重置与生命周期清理
- [x] 1.1 修改 `ListeningPlayerController.play`，在加载不同 clip 时彻底重置 `_autoPause = false` 与 `_lastAutoPausedTurnIndex = null` <!-- id: 1.1 -->
- [x] 1.2 确保 `setAutoPause` 及相关通知逻辑健壮 <!-- id: 1.2 -->

## 2. 底部控制栏优化与解耦
- [x] 2.1 修改 `WorkspacePlayerBar`：将“连续播放（场景内循环）”改名为“自动连播下一条（列表循环）” <!-- id: 2.1 -->
- [x] 2.2 在 `WorkspacePlayerBar` 中增加对 `player.isAutoPause` 的全局可见性支持，当开启句间停顿时渲染可一键解除的提示胶囊 <!-- id: 2.2 -->

## 3. 测试与验证
- [x] 3.1 编写单元测试验证播放不同片段时 `_autoPause` 被自动重置 <!-- id: 3.1 -->
- [x] 3.2 编写 Widget 测试验证在播放条中能观察到句间停顿胶囊并一键恢复连播 <!-- id: 3.2 -->
- [x] 3.3 运行工程测试套件确保全部通过 <!-- id: 3.3 -->

## 4. 本地构建与部署 (GEMINI.md 核心规约)
- [x] 4.1 执行 `./scripts/deploy_local.sh` 重新构建、签名并替换当前本机运行的 `/Applications/V8WorkToolbox.app` <!-- id: 4.1 -->
