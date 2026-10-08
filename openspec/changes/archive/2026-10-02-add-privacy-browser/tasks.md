## 1. 数据层 · 私密浏览器 SQLite 存储

- [x] 1.1 新建 `PrivateBrowserStore.swift`，在隐私空间 App Support 目录下创建/迁移 `PrivateBrowser.sqlite`
- [x] 1.2 定义并创建 `browser_tabs` 表（id, url, title, scroll_x, scroll_y, order_index, created_at）
- [x] 1.3 定义并创建 `browser_bookmarks` 表（id, url, title, favicon_path, created_at）
- [x] 1.4 定义并创建 `homepage_shortcuts` 表（id, name, url, favicon_url, favicon_path, order_index）
- [x] 1.5 定义并创建 `categories` 表（id, name, parent_id, icon, display_order）
- [x] 1.6 定义并创建 `tags` 表（id, name, color, usage_count）
- [x] 1.7 定义并创建 `video_bookmarks` 表（id, title, url, platform, thumbnail_path, duration, added_at, category_id, rating, notes, ai_summary, ai_tags_json）并启用 FTS5 全文索引（title + notes）
- [x] 1.8 定义并创建 `bookmark_tags` 关联表（bookmark_id, tag_id）
- [x] 1.9 编写 `PrivateBrowserRepository.swift`，封装所有 CRUD 操作（tabs、bookmarks、shortcuts、categories、tags、video_bookmarks）

## 2. 浏览器核心 · WKWebView 容器

- [x] 2.1 创建 `PrivateBrowserViewController.swift`（NSViewController），内嵌 `WKWebView`，配置 `WKWebViewConfiguration`（禁用历史存储、关闭 WebSQL 持久化）
- [x] 2.2 实现地址栏（NSTextField）+ 前进/后退/刷新按钮工具栏，绑定 WKWebView navigation delegate
- [x] 2.3 实现多标签页 UI：NSTabView 或自定义标签栏，支持新建 / 关闭 / 切换标签页
- [x] 2.4 实现跨会话标签页持久化：隐私空间解锁时从 `browser_tabs` 恢复所有标签；锁定时将当前所有标签状态写回数据库
- [x] 2.5 实现 N 宫格首页（SwiftUI `HomepageView`）：读取 `homepage_shortcuts` 渲染快捷方式格，点击在当前 Tab 打开 URL；空 Tab 显示此视图
- [x] 2.6 实现首页快捷方式管理：添加（输入 name+URL，异步抓取 favicon 并缓存本地）、删除、拖拽排序
- [x] 2.7 实现书签功能：工具栏「★ 收藏」按钮保存当前页 title+URL+favicon；书签列表侧边栏/下拉；点击书签导航

## 3. 网络代理集成

- [x] 3.1 创建 `PrivateBrowserProxyHandler.swift`（`WKURLSchemeHandler`），拦截 `http://` 和 `https://` 请求，通过 URLSession（注入 proxy-manager 的 `ProxyConfiguration`）转发
- [x] 3.2 在 `WKWebViewConfiguration` 中注册自定义 Scheme Handler，并从 proxy-manager 读取当前代理配置，在代理状态变更时通知浏览器更新
- [x] 3.3 验证 YouTube、MissAV 等目标站点在代理开启 / 关闭时均可正常加载

## 4. 视频增强浮层工具栏

- [x] 4.1 编写 `VideoDetectorScript.js`（WKUserScript）：通用 MutationObserver 检测 `<video>` 元素出现；向 native 发送 `videoDetected` message（含 videoSrc、platform hint）
- [x] 4.2 为已知平台（YouTube、MissAV、PornHub、jav.sb、91porn、pornlulu）编写平台适配 JS 片段，监听视频播放事件并补充 og:title / og:image 元数据
- [x] 4.3 创建 `VideoEnhancerToolbar.swift`（NSView），包含「下载」「缓存播放」「收藏」「字幕」四个按钮，固定悬浮在浏览器 chrome 底部（不注入 DOM）
- [x] 4.4 实现「下载」按钮：调用现有 yt-dlp 下载队列，传入当前页 URL，下载进度反馈到按钮 badge
- [x] 4.5 实现「缓存播放」按钮：调用下载队列，下载完成后自动调用私密播放器打开该本地文件
- [x] 4.6 实现「收藏」按钮：提取当前页元数据（title、URL、platform、og:image URL），创建 VideoBookmark 记录，触发 AI 自动打标（Task 8.1），写入 video_bookmarks
- [x] 4.7 实现「字幕」按钮：弹出字幕面板，提供「快速提取（yt-dlp）」和「AI 生成（STT）」两个选项

## 5. 浏览器内字幕 Overlay

- [x] 5.1 编写 `SubtitleBridgeScript.js`（WKUserScript）：在 video 播放时以 250ms 间隔通过 `window.webkit.messageHandlers.subtitleTime.postMessage` 发送 `currentTime`
- [x] 5.2 创建 `BrowserSubtitleOverlayView.swift`（NSView），覆盖在 WKWebView frame 之上，根据收到的 currentTime 查找对应字幕段并渲染（CATextLayer，半透明背景，居底部）
- [x] 5.3 实现字幕数据挂载接口：接收 `[SubtitleSegment]`（start, end, text），替换当前字幕集
- [x] 5.4 实现字幕显隐 Toggle（默认 off），在新页面加载时重置为 off
- [x] 5.5 处理视频全屏（Fullscreen API）场景：监听 `webkitfullscreenchange`，全屏时将 Overlay 重新定位到覆盖整个 window

## 6. 字幕面板 · 两条生成路径

- [x] 6.1 创建 `BrowserSubtitlePanel.swift`（NSPanel / SwiftUI sheet）：展示「快速提取」和「AI 生成」选项，以及进度状态和结果预览
- [x] 6.2 实现「快速提取」路径：调用现有 yt-dlp 字幕提取能力（`--write-auto-sub --sub-lang zh,en`），解析 .srt 文件，挂载到 BrowserSubtitleOverlayView
- [x] 6.3 实现「AI 生成」路径：调用现有 AI STT pipeline（Whisper/MiMo），生成字幕后挂载 Overlay；支持翻译为中文
- [x] 6.4 字幕面板支持导出按钮（保存 .srt 到用户选择路径）

## 7. 私密视频收藏库 UI

- [x] 7.1 创建 `VideoLibraryView.swift`（SwiftUI）：左侧分类树面板 + 右侧视频列表，整体融入隐私空间导航
- [x] 7.2 实现分类树：展示多级 Category，支持展开/折叠、新建子分类、重命名、删除（级联移动子书签到「未分类」）
- [x] 7.3 实现标签云面板：展示所有 Tag（按 usage_count 排序），点击标签过滤列表
- [x] 7.4 实现视频列表：展示 VideoBookmark（64×44 圆角缩略图、标题、平台、评分、标签 chips），支持按分类/标签/平台/评分/日期过滤和排序
- [x] 7.5 实现全文搜索栏（FTS5 查询 title + notes）
- [x] 7.6 实现 VideoBookmark 详情视图：显示/编辑 title、notes、rating（星级）、category、tags、ai_summary
- [x] 7.7 实现缩略图本地缓存：收藏时异步下载 og:image 到 `~/.../PrivateBrowser/thumbnails/`，列表中展示本地缓存图
- [x] 7.8 实现 VideoBookmark 来自私密播放器收藏数据扩展：在播放器收藏数据模型中添加 `source_url` / `platform` / `ai_summary` 字段，并在收藏库视图中展示平台 badge（适配 private-media-player delta spec）
- [x] 7.9 实现 video-downloader 下载入口扩展：下载任务记录增加 `triggeredBy: .browser` 来源字段，下载完成/失败状态回调给 VideoEnhancerToolbar 的按钮 badge（适配 video-downloader delta spec）

## 8. AI 能力层

- [x] 8.1 实现自动打标签（`AILibraryTaggingService.swift`）：收藏时 fire-and-forget async Task，发送 title + platform + og:description 给 Text LLM slot，解析返回 JSON（tags 数组 + category 建议），写入 `ai_tags_json`，在书签行显示 spinner → 结果 badge
- [x] 8.2 实现手动重新分析入口：详情视图「AI 重新分析」按钮，调用同一 service，结果覆盖现有 ai_tags + ai_summary
- [x] 8.3 实现语义检索（`AISemanticSearchService.swift`）：自然语言查询先通过 FTS5 取 top-200 候选，再发给 Text LLM slot 排序，返回 bookmark ID 排序列表，驱动列表刷新
- [x] 8.4 实现 AI 咨询面板（`AILibraryChatPanel.swift`，SwiftUI）：悬浮在收藏库工具栏，支持多轮对话；系统 prompt 包含用户收藏摘要（分类树 + 最近 50 条书签标题）；支持询问当前浏览器页面视频信息（传入当前 URL + og 元数据）
- [x] 8.5 确保 AI 层仅使用本地元数据（title、tags、notes、platform），不发送视频帧或音频

## 9. 隐私空间导航集成

- [x] 9.1 在隐私空间侧边栏导航中添加「私密浏览器」和「视频收藏库」两个入口
- [x] 9.2 确保浏览器和收藏库均受隐私空间 PIN 锁保护（锁定时清空内存中的 WKWebView 快照，持久化状态仅在解锁后加载）
- [x] 9.3 确保「私密浏览器」从全局搜索和 All Tools 视图中排除（遵循 privacy-space isolation spec）

## 10. 测试与验收

- [x] 10.1 验证 YouTube、MissAV、PornHub、jav.sb、91porn、pornlulu 在代理开启状态下均可正常加载
- [x] 10.2 验证视频检测浮层在上述 6 个平台均正确显示（含播放中检测）
- [x] 10.3 验证「下载」「缓存播放」功能调用 yt-dlp 并在私密播放器正常打开
- [x] 10.4 验证「快速提取字幕」在 YouTube / Bilibili 成功获取字幕并在 Overlay 同步显示
- [x] 10.5 验证跨会话标签页持久化：关闭再打开隐私空间，标签页恢复
- [x] 10.6 验证 PIN 锁定时 WKWebView 内容被隐藏，解锁后状态恢复
- [x] 10.7 验证 AI 自动打标签在收藏后触发并在数秒内显示结果
- [x] 10.8 验证语义检索返回符合预期的排序结果（手动测试 3 条查询）
- [x] 10.9 验证收藏库分类树多级 CRUD 操作无数据异常
- [x] 10.10 验证 video-downloader 和 private-media-player 的扩展字段在 UI 中正确展示
