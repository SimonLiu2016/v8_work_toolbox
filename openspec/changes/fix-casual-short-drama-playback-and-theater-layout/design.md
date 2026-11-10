# 架构与设计：随心短剧播放流与桌面剧场布局重构

## 1. 系统架构
本变更聚焦在两个关键层面：
1. **网络与协议适配层（Data Layer）**：
   - 修复与上游 HGhub 真实 API 的流协议对接。
   - `HuangguoApiClient.getPlayInfo(dramaId, epNum)`：
     - 请求方式：`_request(method: 'POST', path: '/api/videos/$dramaId/episodes/$epNum/playback')`
     - 数据解析：
       ```dart
       final data = response['data'] as Map<String, dynamic>? ?? {};
       final streams = data['streams'] as Map<String, dynamic>? ?? {};
       final mainStream = streams['main']?.toString() ?? '';
       final hevcStream = streams['hevc']?.toString() ?? '';
       final legacyUrl = data['video_url']?.toString() ?? '';
       final realVideoUrl = mainStream.isNotEmpty ? mainStream : (hevcStream.isNotEmpty ? hevcStream : legacyUrl);
       ```
     - 结构映射回 `DramaPlayInfo`，确保下游控制器无感知调用。

2. **视图表现与布局层（UI Presentation Layer）**：
   - **两态状态机**：
     - `CasualShortDramaController.currentDrama == null` $\implies$ 片库探索态（`_buildBrowseView()`）
     - `CasualShortDramaController.currentDrama != null` $\implies$ 大屏剧场态（`_buildTheaterView()`）
   - **浏览态**：
     - 搜索栏 + 分类 Tab + 自适应全宽 GridView 卡片流（根据屏幕宽度动态自适应 4~8 列）。
     - 点击卡片触发 `controller.selectDrama(drama)`，平滑切换入剧场态。
   - **剧场态**：
     - 顶部导航条：优雅的「返回片库」按钮 + 当前短剧标题与当前集数标识。
     - 水平分割布局：
       - 主播放区（Flex 7 或 Expanded 占大头）：`DramaTheaterSurface`，纯黑沉浸底色，视频按照 16:9 宽屏或原始比例保持居中，带播放控制条。
       - 右侧选集区（Fixed 320px 或 Flex 3）：`DramaEpisodeDrawer`，展示全部集数按钮、当前正在播放集高亮、选集快速滚动定位。
   - **滤镜修复**：
     - 移除 `BackdropFilter` 引起的 RenderBox 溢出灰斑，确保全屏视觉干净纯粹。
