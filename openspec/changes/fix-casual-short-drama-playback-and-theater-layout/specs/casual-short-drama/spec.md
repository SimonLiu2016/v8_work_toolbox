# casual-short-drama 规约

## 概述
随心短剧工具为用户提供流畅、无广告、纯净的短剧聚合流媒体体验。

## 需求与特性

### 播放流获取与解析 (Playback Stream Resolution)
- **POST Playback 端点集成**：必须通过 `POST /api/videos/<id>/episodes/<ep>/playback` 请求获取真实可播放的视频切片流。
- **流地址提取**：优先从响应 `data.streams.main` 获取 m3u8 地址，若为空则检查 `data.streams.hevc`，最后兼容旧结构 `data.video_url`。
- **播放状态响应**：流地址解析成功后，播放控制器能够立即初始化视频流并正常播放；解析失败时给出重试或提示。

### 桌面端两态布局 (Desktop Two-State Theater Layout)
- **浏览态 (Browse Mode)**：未选中任何视频剧目时（`currentDrama == null`），界面以全宽网格展示短剧分类、搜索栏与精美海报卡片流，无被挤压的侧边多余黑边。
- **观影态 (Theater Mode)**：点击任一剧目后进入观影态，主视区占据屏幕主要宽度（约 70%~75%），以大屏 16:9 比例自适应播放视频；右侧（约 25%~30%）显示选集与剧集信息面板。
- **快速返回**：观影态左上角提供清晰的「返回片库」按钮，点击后平滑退回全宽浏览态，同时保留选集播放记录。

### 渲染与滤镜边界隔离 (Render Boundary Isolation)
- **消除灰色遮挡层**：严禁在未受约束的全局层级使用未裁切的 `BackdropFilter`，剧场背景采用纯黑底色与带 `ClipRect` 保护的容器，防止高斯模糊溢出造成前序组件模糊灰化。
