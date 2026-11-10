# 提案：随心短剧桌面真全屏播放与全库 3300+ 部无限加载支持

## 1. 背景与动机
用户在体验「随心短剧」桌面端时提出两点关键需求：
1. **播放器全屏点击无反应**：目前的全屏按钮仅切换了内部布尔值与图标，未接入 macOS 原生窗口全屏 API，且未隐藏侧边选集抽屉和导航，未能提供真正的沉浸式全屏观影体验；
2. **片库显示短剧数量少且缺少“全部”入口**：上游 HGhub 实际拥有 3337 部短剧（167 页），但当前客户端仅写死拉取第 1 页 20 部，缺乏分页触底自动追加加载（Infinite Scroll），分类栏中也缺少一览全库的「全部」Tab。

## 2. 核心方案
1. **接入桌面原生全屏体系（Native Window Fullscreen）**：
   - 接入 `window_manager` 的 `windowManager.setFullScreen(bool)`；
   - 点击全屏按钮或按键盘快捷键 `F` 触发全屏，按 `Esc` 或 `F` 退出全屏；
   - 全屏状态下自动收起右侧选集抽屉，视频在屏幕正中央沉浸居中；鼠标静止 3 秒后控制条自动渐隐，鼠标晃动重新显现。
2. **全库 3300+ 部短剧探索与触底无限加载（Infinite Scroll）**：
   - 分类 Tab 首位置顶「全部 (3300+部)」；
   - 控制器维护 `currentPage`、`hasMore` 与 `isLoadingMore` 状态，支持 `loadMoreCatalog()` 无缝追加分页数据（每页拉取 30~40 部）；
   - 在片库大网格中绑定 `ScrollController`，滑至距底部 200px 时自动触发静默加载下一页，底部呈现“正在加载更多精彩...”或“已加载全部短剧”指示器。

## 3. 影响范围
- `lib/tools/casual_short_drama/services/huangguo_api_client.dart`
- `lib/tools/casual_short_drama/services/casual_short_drama_controller.dart`
- `lib/tools/casual_short_drama/ui/casual_short_drama_page.dart`
- `lib/tools/casual_short_drama/ui/drama_theater_surface.dart`
- `test/casual_short_drama_api_test.dart`
