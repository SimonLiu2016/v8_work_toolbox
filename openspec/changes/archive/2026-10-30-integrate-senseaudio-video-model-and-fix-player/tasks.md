## 1. 系统全局配置层升级 (AiConfigStore & UI)

- [x] 1.1 在 `lib/services/ai_config_store.dart` 中为 `AiProviderConfig` 扩展 `videoModels` 字段，支持 JSON 序列化与向后兼容
- [x] 1.2 在 `lib/services/ai_config_store.dart` 的标准槽位列表中增加 `'video'` 槽位，维护候选绑定列表持久化
- [x] 1.3 在 `lib/shell/ai_config_page.dart` 中添加「视频模型 (Video)」槽位展示与候选配置，提供 SenseAudio 预设模型模板 (`doubao-seedance-2-0-260128`，BaseUrl: `https://api.senseaudio.cn`)

## 2. SenseAudio 视频适配器与工坊调度引擎重构

- [x] 2.1 在 `lib/tools/ai_video_studio/services/video_gen_adapter.dart` 中实现 `SenseAudioVideoAdapter`，实现首帧 Base64 编码上传、POST `/v1/video/create` 任务创建、GET `/v1/video/status` 轮询、进度回调与 mp4 自动下载落盘
- [x] 2.2 重构 `VideoGenAdapterFactory.create`，优先从 `AiConfigStore` 的 `video` 槽位读取绑定的首选供应商与视频模型，若为 SenseAudio 则创建对应适配器，未配云端时回退至本地 Ken Burns
- [x] 2.3 当系统未配置视频模型且本机未安装 FFmpeg 时，在分镜卡片点击「视频」时弹出友好引导对话框（提供直达「AI能力配置」按钮）

## 3. 分镜看板播放器弹窗容错与交互安全返回

- [x] 3.1 在 `lib/tools/ai_video_studio/ui/storyboard_board.dart` 的 `_MediaPreviewDialog` 中增加 `Focus` 与 ESC 键监听，按下 ESC 键瞬时返回看板
- [x] 3.2 优化弹窗视口约束：使用 `AspectRatio` 约束视频播放区域，并在视频加载及首帧渲染完成前展示分镜关键帧大图垫底
- [x] 3.3 监听 `Player` 的错误流与缓冲状态，在播放异常或视频损坏时优雅降级显示关键帧与错误提示，并提供「系统播放器打开」按钮
- [x] 3.4 顶部常驻显式的「← 返回分镜看板」按钮，并确保点击外部半透明遮罩能正常退出

## 4. 验证与本地部署

- [x] 4.1 运行 `flutter analyze` 确保全局无类型与代码静态错误
- [x] 4.2 编写与运行单元测试验证 `video` 槽位读写、SenseAudio 请求体组织与状态解析
- [x] 4.3 执行 `./scripts/deploy_local.sh` 重新构建并部署至本地应用
