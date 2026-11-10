# 任务分解：add-drama-fullscreen-and-infinite-catalog

- [x] 1. 实现桌面原生全屏观影支持
  - [x] 1.1 在 `DramaTheaterSurface` 中引入 `windowManager.setFullScreen` 与平台通道联动
  - [x] 1.2 增强快捷键处理（支持 `F` 全屏、`Esc` 退出全屏）与组件销毁时的窗口恢复
  - [x] 1.3 优化全屏沉浸体验（隐藏侧边抽屉、鼠标静止自动隐退控制栏）
- [x] 2. 实现全部短剧 Tab 与无限滚动分页加载
  - [x] 2.1 在 `HuangguoApiClient` 中增强 `getFeed` 分页支持（单页 30 部）
  - [x] 2.2 在 `CasualShortDramaController` 中维护分页状态与 `loadMoreCatalog()` 异步追加逻辑
  - [x] 2.3 在 `CasualShortDramaPage` 分类栏首位加入「全部 (3300+部)」Tab
  - [x] 2.4 在海报网格中绑定 `ScrollController` 触底自动追加与底部加载状态呈现
- [x] 3. 验证与本地发布
  - [x] 3.1 运行单元测试与静态代码分析（`flutter analyze`）
  - [x] 3.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用
