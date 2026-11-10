# 提案：随心短剧播放流接口升级与桌面两态观影布局重构

## 1. 背景与动机
在第一版「随心短剧」上线后，用户在 macOS 桌面端实际体验中遇到两个关键问题：
1. **左侧大块灰色且无内容**：在点击视频后，左侧海报或目录栏区域呈现大面积灰色空白模糊层，破坏正常交互。
2. **播放器窗口微缩且点击播放无反应**：三栏挤压导致播放器被压成狭窄的竖条；且调用上游废弃的 `GET /api/videos/:id/play?ep=:ep` 返回空流地址（`video_url: ""`），导致播放器无法加载并播放真实的视频切片流。

## 2. 核心方案与变更
1. **播放流接口升级**：
   - 切换到 HGhub 最新生效的播放流端点：`POST /api/videos/<id>/episodes/<ep>/playback`（通过 edge envelope 请求）。
   - 解析返回结果中的 `data.streams.main`（或 `hevc`），获得真实有效的 m3u8 切片流，并向下兼容旧字段。
2. **去除 BackdropFilter 全局穿透与渲染溢出**：
   - 去除原有未受约束的全局高斯模糊 `BackdropFilter`（该滤镜导致上层模糊溢出覆盖左侧区域呈现灰色块）。
   - 采用带 `ClipRect` 的纯黑沉浸底色，确保渲染边界受控且无光晕/灰斑污染。
3. **桌面端两态布局（Browse & Theater Modes）**：
   - **浏览态（Browse Mode）**：未选中剧集时，界面呈现全宽大网格片库探索（搜索栏、分类 Tab、海报卡片流），充分利用桌面屏幕空间。
   - **观影态（Theater Mode）**：选中剧集后，界面自动切换为大屏观影模式——左侧/主视区占据约 70%~75% 宽度的自适应宽屏播放器，右侧 25%~30% 常驻选集抽屉（支持选集切换、倍速/清晰度选择及折叠）；顶部提供明确的「返回片库」操作。

## 3. 影响范围
- `lib/tools/casual_short_drama/services/huangguo_api_client.dart`
- `lib/tools/casual_short_drama/services/casual_short_drama_controller.dart`
- `lib/tools/casual_short_drama/ui/casual_short_drama_page.dart`
- `lib/tools/casual_short_drama/ui/drama_theater_surface.dart`
- `lib/tools/casual_short_drama/ui/drama_episode_drawer.dart`
- `test/casual_short_drama_api_test.dart`
