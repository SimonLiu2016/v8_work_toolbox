## 1. 服务层会话隔离改造

- [x] 1.1 在 `SecurityAgentService` 中定义 `SessionAgentData` 类并以 `sessionId` 为键建立多会话状态池
- [x] 1.2 在 `SecurityAgentService` 中增加 `switchSession(String? sessionId)` 和 `removeSession(String sessionId)` 方法，并在切换时广播对应的状态与步骤流
- [x] 1.3 在 `SecurityAgentService.run` 中记录当前会话的 `sessionId`，使状态更新精确写入该会话切片

## 2. 界面与渲染改造

- [x] 2.1 在 `SecurityAgentView` 中引入 `AppMarkdownView`，替换 `_buildFinalReport` 中的纯 `Text` 组件
- [x] 2.2 在 `SecurityAgentView` 中监听 `controller` 的当前会话变化并调用 `switchSession`，让思考日志与建议报告随会话切换即时联动
- [x] 2.3 在 `SecuritySessionController.deleteSession` 中联动清理对应会话的 Agent 状态缓存

## 3. 验证与本地部署

- [x] 3.1 运行单元测试并执行 `flutter analyze` 确保无报错
- [x] 3.2 运行 `./scripts/deploy_local.sh` 编译并热更新本地 `/Applications/V8WorkToolbox.app`
