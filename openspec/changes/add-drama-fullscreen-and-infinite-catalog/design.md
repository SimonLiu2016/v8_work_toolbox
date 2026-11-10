# 架构与设计：全屏播放与片库无限加载

## 1. 桌面原生全屏实现架构
- **平台层调用**：
  - 引入 `package:window_manager/window_manager.dart`；
  - `_toggleFullscreen()` 实现：
    ```dart
    final nextFullscreen = !_isFullscreen;
    setState(() => _isFullscreen = nextFullscreen);
    await windowManager.setFullScreen(nextFullscreen);
    ```
  - 当退出页面或离开剧场时，确保在 `dispose()` 或退出观影态时恢复窗口常规模式（`windowManager.setFullScreen(false)`）；
  - `KeyEvent` 监听：捕获 `LogicalKeyboardKey.escape` 与 `LogicalKeyboardKey.keyF` 切换全屏。
- **UI 联动**：
  - 在全屏模式下通知上层父页面折叠选集抽屉（或全屏组件自身占满全屏）。
  - 配合 `Timer` 实现 3 秒鼠标悬停无操作自动将 `_showControls` 置为 `false`，移动时恢复。

## 2. 片库全库与无限滚动设计
- **API 层适配**：
  - `HuangguoApiClient.getFeed({int page = 1, int size = 30})`，默认单页拉取 30 部短剧；
- **控制器层分页管理 (`CasualShortDramaController`)**：
  - 增加状态变量：
    - `int catalogPage = 1;`
    - `bool hasMoreCatalog = true;`
    - `bool isLoadingMoreCatalog = false;`
    - `int totalDramasCount = 3337;`
  - 新增方法 `loadMoreCatalog()`：
    - 若 `isLoadingMoreCatalog || !hasMoreCatalog` 则直接 return；
    - 请求 `catalogPage + 1`；
    - 将新返回的 `DramaCard` 过滤去重后追加进 `catalogItems`；
    - 若返回数据条数小于 `size`，则 `hasMoreCatalog = false`；
  - `switchTab('all')` 或搜索关键词时重置 `catalogPage = 1, hasMoreCatalog = true`。
- **视图层触底监听 (`CasualShortDramaPage`)**：
  - 为 `GridView` 配置 `ScrollController`；
  - 监听 `scrollController.position.pixels >= scrollController.position.maxScrollExtent - 250` 时，触发 `_controller.loadMoreCatalog()`；
  - 底部追加 `SliverToBoxAdapter` / 底部指示器组件。
