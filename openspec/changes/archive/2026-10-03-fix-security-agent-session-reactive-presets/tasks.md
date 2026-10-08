## 1. 会话草稿与推荐任务服务层支持

- [x] 1.1 在 `SessionAgentData` 中增加 `taskDraft` 字段并在 `reset()` 中正确处理
- [x] 1.2 在 `SecurityAgentService` 中提供 `taskDraft` 读写方法以及基于会话目标的推荐任务生成辅助逻辑

## 2. 界面响应式联动与动态预设

- [x] 2.1 在 `SecurityToolboxMainPage` 中使用 `ListenableBuilder` 监听 `_controller` 重绘当前激活的 Tab 视图
- [x] 2.2 在 `SecurityAgentView` 中响应会话切换：切换时同步该会话的 `taskDraft`，若为空则自动预填该会话的推荐任务
- [x] 2.3 在 `SecurityAgentView` 的一键预设工作流点击回调中动态实时解析当前会话目标，避免闭包陈旧

## 3. 测试与验证

- [x] 3.1 编写并运行单元测试：验证多会话切换时输入框草稿隔离、默认推荐任务自动填充，以及动态目标预设解析
- [x] 3.2 运行 `./scripts/deploy_local.sh` 编译并热更新本地 `/Applications/V8WorkToolbox.app`
