## 1. 速度调整与交互逻辑改造

- [x] 1.1 调整 `KnowledgeGraphView` 自转速度步长为 `0.0012`
- [x] 1.2 在 `_handleTap` 命中有效节点时取消恢复定时器并设置 `_autoRotate = false`
- [x] 1.3 在 `MouseRegion.onExit` 中恢复 `_autoRotate = true`

## 2. 自动化测试与验证

- [x] 2.1 针对自转角速度与交互状态机逻辑编写/更新测试用例
- [x] 2.2 运行全套相关测试验证无回归

## 3. 应用编译构建与发布

- [x] 3.1 编译打包 macOS Release 版本 (`flutter build macos --release`)
- [x] 3.2 覆盖替换部署至 `/Applications/V8WorkToolbox.app` 并重启验证


