## 1. AppListItem 交互与样式重构

- [x] 1.1 改造 `AppListItem` 悬停过渡机制：去除 100ms 缓动延迟，改为即时响应，消除快速划过时的残影频闪
- [x] 1.2 增强 `AppListItem` 的选中态（Selected）与悬停态（Hover）视觉分级：引入左侧 Accent 强调色指示条，并联动前景色高亮
- [x] 1.3 调优浅色模式与深色模式下的悬停背景色对比度（确保浅色模式下与面板底色对比分明、肉眼清晰可见）

## 2. ToolPanel 状态绑定与样式联调

- [x] 2.1 在 `ToolPanel` 的 `ListView.builder` 中为每个 `AppListItem` 增加明确的 `key: ValueKey(tool.id)`
- [x] 2.2 验证 `ToolPanel` 选中工具项与折叠面板、主视区工具切换的联动自洽

## 3. 验证与本地部署

- [x] 3.1 编写/更新 Widget 交互测试，断言悬停即时生效且浅色/深色模式下样式与指示条正确
- [x] 3.2 运行 `flutter analyze` 确保 0 error 0 warning
- [x] 3.3 运行相关测试确保无回归
- [x] 3.4 执行 `./scripts/deploy_local.sh` 编译并本地部署生效

