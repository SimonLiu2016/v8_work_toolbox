## Why

Dola 号池的服务层早已完整（探活、调度、签名、出片适配器），但**没有任何 UI 入口**：`DolaAccountPoolPanel` 在 `lib/` 下零引用，`DolaAccountStore.init()` 无生产调用，工坊设置的引擎下拉里也选不到它。用户看到的结果是"功能不存在"。

同时，`004ea27` 提交的能力声明基于不完整信息：把「我们的适配器没实现图片上传」误读成「Dola 不支持参考图」，写成了 `maxReferenceImages: 0`、`supportsFirstFrame: false`、时长只给 `[5,10,15]`。查上游 `dola-pool2/README.md` 与 `protocol/dola_pure_api.py` 后确认：两个型号都支持参考图（上游上限 10 张），`seedance-2.5` 的时长是 5/10/**30** 秒而非 5/10/15。

## What Changes

- **修正能力声明**：按型号拆分（`2.5` → 5/10/30、`2.0` → 5/10/15），开启 `supportsFirstFrame` 与参考图模式
- **`maxReferenceImages` 改为可空**（`int?`）：`null` 表示不限制。原设计用 `0` 表示"不支持"，但"没测过上限"与"明确不支持"是两回事——用 0 会让 UI 说"不支持参考图"这句假话
- **Dola 能力可配置**：新增号池自己的能力配置层，用户可覆盖时长集合与参考图上限；未配置时回落到内置预设
- **接通入口**：`DolaAccountStore.init()` 接进 `WindowServices.required`；AI 配置页新增「Dola 号池」tab；工坊设置的视频引擎下拉新增 `dola-pool-2.5`
- **适配器兜底按型号走**：`_snapDuration` 不再硬编码 `[5,10,15]`，按 `_model` 取对应合法集合
- **一条失败测试**钉住「参考图上传未实现」这个真实状态，而不是让它假装通过

不改上游 `dola-pool2`，不引入 Docker 部署形态（方案 A 已放弃）。

## Capabilities

### New Capabilities

- `dola-pool-configuration`：号池的能力配置层——可配置项、覆盖优先级、缺省行为，以及配置与内置预设的关系。

### Modified Capabilities

- `dola-account-pool`：补一条 requirement，号池数据与能力配置的初始化时机必须由应用启动保证，而不是等用户打开面板。
- `dola-video-engine`：补「Studio Engine Selection Persistence」的可选引擎项，并修正能力声明的型号差异。

## Impact

- **受影响代码**：`lib/services/media_capability.dart`（字段可空 + 分型号预设）、`lib/tools/dola_pool/`（新增配置 store + 修正兜底）、`lib/main.dart`（服务清单）、`lib/shell/ai_config_page.dart`（新 tab）、`lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`（引擎选项）
- **破坏性变更**：`MediaModelCapability.maxReferenceImages` 由 `int` 改 `int?`。所有 preset 与序列化同步更新；`0` 的既有含义（不支持）保留为 `0`，新增 `null` 表示不限制
- **行为变化**：Dola 路径下的请求不再被错误裁剪。此前 `maxReferenceImages: 0` 会让任何携带参考图的请求被拒——也就是片段级生成在 Dola 路径下必然失败；此后放行
- **测试**：`media_capability_matrix_test` 更新；新增失败测试标记参考图上传待实现；`ai_config_test` 的序列化用例需覆盖 `null`
- **不涉及**：参考图上传的 ImageX 实现（另属后续 change，本 change 只让能力矩阵不再说谎）
