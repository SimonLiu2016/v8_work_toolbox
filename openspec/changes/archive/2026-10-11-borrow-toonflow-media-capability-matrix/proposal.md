## Why

工坊的视频与图像适配器目前对模型参数采用「写死 + clamp」策略：`SenseAudioVideoAdapter` 恒发 `'ratio': '9:16'` 与 `'resolution': '720p'`，时长 `round().clamp(4, 15)`；`AgnesVideoAdapter` 恒发 `'aspect_ratio': '9:16'`，时长 `clamp(4, 12)`。这直接导致上游网关以 `plugin usage enum is not an allowed value` 一类 400 拒绝——`openspec/specs/storyboard-visual-composition` 中的 `Agnes video generation payload contract` 与 `integrate-senseaudio-image-generation` 的分辨率白名单吸附，都是这个缺口的症状性补丁。

对标 Toonflow 的 `packages/providers/src/media/*.ts`：每个模型显式声明 `mode`（`text` / `singleImage` / `startFrameOptional` / `["imageReference:9", ...]`）、`durationResolutionMap`（时长 → 可用分辨率）、`imageSizes` / `imageRatios`，节点侧据此把非法参数吸附到合法值，非法组合直接不给选。工坊需要同一层能力矩阵，否则每次接新模型都要重演一遍「发现 400 → 加一条特判」。

## What Changes

- **新增模型能力矩阵**：为 `AiConfigStore` 中 `video` 与 `image` 槽位已配置的模型声明能力——支持的生成模式、时长集合、分辨率集合、画幅比例、参考图数量上限、是否支持首帧/尾帧、是否支持原生音频。
- **适配器前置校验与吸附**：提交请求前做一次「目标参数 → 模型合法值」的规整：
  - 时长不在白名单 → 吸附到**最近的较小合法值**（保证不超过用户预期，而不是四舍五入到更大值让上游拒）
  - 分辨率/比例不在白名单 → 吸附到合法集合中比例最接近的一项
  - 模式不被支持（如模型不支持多参考而请求带了多张）→ **明确拒绝并提示**，不静默降级提交
  - 全部吸附动作记入 `AiLogger`，用户可在日志里看到「请求 15s 吸附为 12s」这类变更
- **图像适配器多参考图**：`ImageGenRequest.referenceImagePath`（单张）扩展为 `referenceImages`（多张），`ImageGenAdapter` 契约同步更新；不支持多参考的引擎取第一张并记录降级。
- **工坊设置页展示能力**：在「工坊设置」与分镜看板的生成入口展示当前模型的可用时长/比例/参考数量，替代此前只能靠试错发现的方式。
- **非目标**：不改造供应商预设的维护方式（仍由 `ai_config_store.dart` 的预设按钮填写）；不实现 Toonflow 的「运行时从 `/models` 端点拉取能力」的动态发现（需要每家在位供应商实现，超出本变更）；不引入 `AiConfigStore` 的 schema 破坏性变更。

## Capabilities

### New Capabilities

- `media-model-capability-matrix`: 定义模型能力矩阵的声明位置与字段、参数吸附与拒绝规则、降级可见性，以及工坊内对能力信息的呈现。

### Modified Capabilities

- `ai-configuration`: 供应商模型条目需要携带可选的能力声明（时长/分辨率/比例/模式/参考数量），缺省时按协议类型推断保守默认值而不是写死。
- `storyboard-visual-composition`: 视频生成请求的参数不再由适配器各自 clamp 后写死，而是先经能力矩阵规整；由此，`Agnes video generation payload contract` 要求的「不包含非法参数枚举」由矩阵保证，而不是逐条特判补丁。

## Impact

- **修改**：
  - `lib/services/ai_config_store.dart`：`AiProviderConfig` 增加可选的模型能力声明容器（或新增 `MediaModelCapability` 与模型 id 的映射），预设中为 SenseAudio / Agnes 的内置模型填入声明
  - `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`VideoGenRequest` 不变（由片段化变更扩展）；`SenseAudioVideoAdapter` / `AgnesVideoAdapter` / `KlingVideoAdapter` / `KenBurnsVideoAdapter` 增加 `capabilities` 与规整逻辑
  - `lib/tools/ai_video_studio/services/image_gen_adapter.dart`：`ImageGenRequest` 扩展 `referenceImages`；三个云端适配器同步
  - `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`：构造请求时读取角色/场景的多张参考图
  - `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart` / `ui/storyboard_board.dart`：能力展示
  - `lib/services/ai_logger.dart`：吸附与降级记录（复用现有通道）
- **测试**：`test/ai_video_studio_adapter_test.dart` 扩充吸附/拒绝/降级断言；`test/ai_config_test.dart` 增加能力声明序列化；新增 `test/media_capability_matrix_test.dart`。
- **依赖顺序**：本变更与 `refactor-studio-segment-pipeline` 都改 `VideoGenRequest` 与 `ImageGenRequest`。两者都要求请求携带「片段提示词 + 多参考图 + 时长」，字段天然兼容；但**必须先合入片段化变更**，否则矩阵规整会建立在即将被替换的请求形状上。
