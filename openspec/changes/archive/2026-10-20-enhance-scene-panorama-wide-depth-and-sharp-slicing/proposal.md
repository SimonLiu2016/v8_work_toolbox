## Why

用户在实际使用 360° 全景图及无损透视切片时反馈，切片画面“离得太近、显示不全（建筑横梁、飞檐、门楣与地面石砖被严重截断，仅剩中间墙体/立柱）”，且局部被放大后质感发虚软糊。

经几何与像素物理排查，根因在于：
1. **母图机位逼仄**：全景提示词带有 `interior view`，但缺乏“机位后撤、深远大景深”强约束，生图模型（Agnes）往往将相机放置在狭窄走廊或靠近墙壁处，母图本身缺乏空间物理纵深；
2. **切片视场偏窄**：默认 FOV 90° 在 16:9 画幅下垂直视野仅有 $58.7^\circ$（上下各仅 $29^\circ$），在室内拍摄相当于定焦镜头怼脸，无法装下挑高建筑的上下结构；
3. **像素利用率受限**：90° FOV 仅截取 4K 母图（6272 宽）的 25% 宽度（约 1568 像素），插值放大到 1080P 会产生数码变焦软糊感；
4. **平视构图局限**：建筑重心多在视平线上方，纯水平切片易丢掉屋檐顶棚。

为了保证最终生成的各个机位图片既**“完整宏大”**又**“清晰锐利”**，需要系统化升级全景母图生成提示词、切片视场角规格（105° 电影超广角）、边缘锐化采样滤波，并打通 3D 漫游视口自定视角一键切片。

## What Changes

- **全景生图提示词强化大空间纵深**：在 `ScenePromptBuilder.buildPanoramaPrompt` 中注入 `wide establishing shot, deep perspective, spacious wide interior with vast depth of field, high vaulted ceiling, panoramic vista, distant camera viewpoint pulled back` 等机位后撤、挑高大殿、深远大景深约束，从源头确保母图具有开阔的物理回旋空间。
- **切片视场角全面升级至 105° 电影超广角**：
  - 默认切片 FOV 从 90° 调整为 105°，垂直视场从 $58.7^\circ$ 跃升至 $73.5^\circ$（视野容纳高度增加 25%），横向覆盖提升至近 30%，完整容纳房梁、吊顶与地面进深；
  - 4K 母图原生提取像素物理宽度达 1830 像素，在 1080P 下达到近 1:1 点对点物理直出，消除因低像素裁切数码放大导致的虚焦感。
- **图像后处理引入自适应边缘锐化滤波（Unsharp Masking）**：在重采样双线性插值后施加高频边缘反差微补偿，消除几何重映射带来的高频平滑，让石砖砖纹、木雕棱角更清脆锐利。
- **3D 漫游视口参数全链路联动（所见即切）**：
  - `SceneCard` 新增 `panoramaFov` 与 `panoramaPitchOffset` 属性持久化；
  - 3D 漫游视口中创作者滚动滚轮缩放的最佳 FOV 与微调抬头的俯仰角（Pitch），在点击“🎯 设为基准并切片”时同步记录为场景全局切片基准，真正实现“所见即切”。

## Capabilities

### New Capabilities

*(无新增独立顶层 Capability，均在现有全景投影架构上深化演进)*

### Modified Capabilities

- `ai-video-studio/scene-360-panorama-projection`: 升级全景母图大空间远景提示词生成规范、升级 105° 电影级超广角投影切片与边缘锐度增强滤波、支持 3D 漫游视角 FOV 与 Pitch 参数联动四向切片。

## Impact

- **代码模块**：
  - `lib/tools/ai_video_studio/models/studio_models.dart`: 更新 `SceneCard` 数据模型与 `ScenePromptBuilder`；
  - `lib/tools/ai_video_studio/services/spherical_perspective_slicer.dart`: 更新 `BatchSliceRequest` 默认 FOV 与 Pitch 计算，新增锐化后处理核；
  - `lib/tools/ai_video_studio/ui/panorama_3d_viewer_dialog.dart`: 将视口当前 FOV 和 Pitch 传递至切片回调；
  - `lib/tools/ai_video_studio/ui/series_page.dart`: 联动更新切片请求参数与持久化字段。
- **测试用例**：
  - `test/spherical_perspective_slicer_test.dart`: 增加大景深提示词验证、105° 视场角像素计算与 FOV/Pitch 场景持久化测试。
