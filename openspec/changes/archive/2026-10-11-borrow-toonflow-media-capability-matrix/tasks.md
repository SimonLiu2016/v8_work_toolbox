## 1. 能力模型与解析

- [x] 1.1 新增 `lib/services/media_capability.dart`：`MediaModelCapability`（`modes`、`durations`、`durationResolutions`、`resolutions`、`ratios`、`maxReferenceImages`、`supportsFirstFrame`、`supportsLastFrame`、`supportsNativeAudio`、`isDeclared`）+ `fromJson`/`toJson`/`copyWith`
- [x] 1.2 `MediaCapabilityResolver.resolve(providerId, modelId)`：查 `mediaCapabilities`，未命中按 `AiProtocolType` 取保守默认（openai / agnes / 未知三档），默认的 `isDeclared` 为 false
- [x] 1.3 `test/media_capability_matrix_test.dart`：声明命中、默认回退、`isDeclared` 区分、未知协议的默认取值

## 2. 配置存储扩展

- [x] 2.1 `AiProviderConfig` 增加 `Map<String, MediaModelCapability> mediaCapabilities`，`toJson`/`fromJson` 同步；旧 `ai_config.json` 无该字段时为空 map 且不报错
- [x] 2.2 为 SenseAudio 与 Agnes 的内置视频/图像模型填入能力声明（时长、分辨率、比例、参考数量、首帧/尾帧、原生音频），来源记入注释
- [x] 2.3 `test/ai_config_test.dart`：能力声明的序列化往返；旧配置文件加载后能力为空

## 3. 请求规整层

- [x] 3.1 新增 `MediaRequestNormalizer`：时长向下取整吸附、分辨率/比例按比例距离吸附、参考数量截断；返回规整后的请求与变更列表
- [x] 3.2 不被支持的能力维度（无参考能力却带参考图、不支持首帧却指定首帧、模式不在集合内）→ 抛可读错误，不降级提交
- [x] 3.3 `NormalizingVideoAdapter` / `NormalizingImageAdapter` 包装类，暴露 `unwrap()`
- [x] 3.4 `VideoGenAdapterFactory.create` / `ImageGenAdapterFactory.create` 返回包装后的适配器
- [x] 3.5 `SegmentVideoGenTask` 中 `forceLocalKenBurns` 判断改用 `unwrap()` 后再做类型比较
- [x] 3.6 单元测试：15s→12s 吸附、1080p→720p 吸附、比例距离选择、参考数截断、三类拒绝场景、`unwrap()` 返回内层

## 4. 图像多参考图

- [x] 4.1 `ImageGenRequest` 增加 `referenceImages: List<String>`，保留 `referenceImagePath` 作为兼容访问器（取列表首项）
- [x] 4.2 `SystemAiImageAdapter` / `SenseAudioImageAdapter` / `SiliconFlowImageAdapter` / `LocalStubImageAdapter` 支持多参考；不支持多参考的取首张并记录降级
- [x] 4.3 `SenseAudioImageAdapter` 原有的私有分辨率吸附逻辑替换为矩阵规整，删除重复实现
- [x] 4.4 `studio_generation_tasks.dart` 的 `ImageGenTask` 读取角色与场景的多张参考图并按序传入
- [x] 4.5 测试：多参考按序传递、单图引擎降级可见、SenseAudio 走统一规整路径

## 5. 日志与 UI 呈现

- [x] 5.1 吸附与降级经 `AiLogger` 记录：模型 id、原始值、规整值、截断的参考图数量
- [x] 5.2 `studio_settings_dialog.dart` 展示当前视频/图像模型的能力摘要（时长集合、比例集合、参考数量上限），未声明时标注「默认能力，未经确认」
- [x] 5.3 分镜看板生成结果区展示「本次提交的实际参数」与用户请求值并列
- [x] 5.4 测试：一次发生吸附的生成会在日志中留下对应记录；设置页对未声明模型展示默认标注

## 6. 回归与收尾

- [x] 6.1 `test/ai_video_studio_adapter_test.dart` 全量更新（适配器被包装后的行为）
- [x] 6.2 手工验证端到端：请求 15s 的 drama 片段生成，确认提交为 12s、日志有记录、看板显示实际参数
- [x] 6.3 全量回归：`flutter test` 通过；`flutter analyze --no-fatal-infos` 无新增 error/warning
- [x] 6.4 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh` 并确认部署实例正常运行
