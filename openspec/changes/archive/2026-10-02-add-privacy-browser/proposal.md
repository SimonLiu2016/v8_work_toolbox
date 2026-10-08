## Why

隐私空间目前提供私密影音播放器，但用户常看的视频内容大多分布在 YouTube、MissAV、PornHub、jav.sb、91porn、pornlulu 等网页平台，每次需要借助外部浏览器打开，无法享受隐私空间的保护，也无法与私密播放器、AI 字幕、视频下载等已有能力联动。通过内置私密浏览器，将网页视频体验完整纳入隐私空间，同时叠加 AI 智能标签、语义检索和收藏库管理，打造一个统一的私密影音中心。

## What Changes

- **新增**：隐私空间内置私密浏览器（WKWebView 多标签页，含书签、跨会话标签页持久化）
- **新增**：N 宫格快捷网站首页，支持用户自定义站点（无浏览历史记录）
- **新增**：视频增强浮层工具栏（检测到 `<video>` 元素后浮现），含一键下载、缓存播放、收藏、字幕入口
- **新增**：浏览器内实时字幕 Overlay（yt-dlp 快速提取路径 + AI STT 路径两级降级）
- **新增**：私密视频收藏库，支持多级分类树 + 多标签体系 + 1-5 星评分 + 用户备注
- **新增**：AI 智能打标签（收藏时自动触发 + 支持手动重新分析）
- **新增**：AI 语义检索（自然语言查询收藏库）
- **新增**：AI 咨询面板（可询问收藏管理、当前页视频信息等）
- **扩展**：复用网络代理管理器，为 WKWebView 注入代理配置
- **扩展**：复用 yt-dlp 下载队列，从浏览器内直接触发下载任务
- **扩展**：复用 AI 字幕能力，支持网页视频下载后在私密播放器内生成字幕

## Capabilities

### New Capabilities

- `private-browser`: 隐私空间内置 WKWebView 浏览器，含多标签页、书签、跨会话持久化、N 宫格快捷首页、网络代理集成
- `private-browser/video-enhancer`: 视频增强浮层，在浏览器内检测视频元素后浮现工具栏，提供下载、缓存播放、收藏、实时字幕功能
- `private-browser/browser-subtitle-overlay`: 浏览器内字幕 Overlay 渲染层，与 WKWebView 视频播放进度同步
- `private-browser/video-library`: 私密视频收藏库，多级分类 + 多标签 + 评分 + 备注的持久化管理系统
- `private-browser/ai-library-assistant`: AI 辅助层，含智能打标签、语义检索、AI 咨询面板，基于全局 AI 配置槽运行

### Modified Capabilities

- `private-media-player`: 扩展收藏数据模型，支持接收来自私密浏览器的网页视频条目（含平台来源、原始 URL 字段）
- `video-downloader`: 扩展下载队列入口，允许从浏览器内工具栏直接触发下载任务并回传进度

## Impact

- **新增依赖**：WKWebView（macOS 原生，无额外引入），SQLite 收藏库存储（已有基础）
- **新增本地存储**：私密收藏库数据库（分类、标签、视频记录、标签页持久化状态）
- **AI 槽调用**：智能打标签 + 语义检索使用全局 Text LLM 槽；字幕 STT 路径复用全局 STT 槽
- **代理集成**：WKWebView 使用 URLSession/NSURLProtocol 代理注入，与现有 proxy-manager 共享配置
- **JS 注入**：视频检测、currentTime 监听、工具栏浮现通过 WKUserScript 实现，需处理各平台 CSP 差异
- **受影响模块**：隐私空间导航（新增浏览器入口）、私密播放器（收藏数据模型扩展）、视频下载器（入口扩展）
