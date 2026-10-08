## Why

用户在系统全局「AI能力配置」中成功配置了 SenseAudio 供应商与 `video` 视频模型槽位，但在进入「AI 短视频工坊」打开「工坊设置」时，视频生成引擎下拉列表仅提供写死的旧选项（`local-kenburns-ffmpeg` 和 `kling-i2v`），无法查看、选择或应用全局已配置的 SenseAudio 模型，导致配置割裂、界面与底层脱节、体验困惑。

为了消除这种割裂感，工坊设置需要与系统的全局 AI 能力槽位打通，支持默认跟随系统 AI 视频与图像模型配置，显示当前继承的模型名称与状态，并支持在工坊内直接进行连通性测试与快速跳转系统配置。

## What Changes

- **工坊设置支持系统 AI 能力槽位继承**：
  - 视频生成引擎下拉列表新增并默认选中「🌟 跟随系统配置（当前: 供应商名 - 模型名）」；
  - 选中系统配置时，动态展示当前绑定的视频大模型名称（如 SenseAudio - doubao-seedance-2-0-260128）与密钥托管状态；
  - 提供快捷按钮「前往系统 AI 配置」，支持一键打开系统 AI 基础设施配置页面。
- **工坊设置引擎连通性与可用性测试升级**：
  - 在「工坊设置」点击「测试可用性」时，针对跟随系统配置的视频模型动态调用对应的 Adapter 验证 Key 有效性与网络连通性，并给出直观的「通过 / 失败」指示。
- **保留独立配置灵活性**：
  - 用户仍可在工坊设置中主动切换至「本地 Ken Burns（免费）」或单独的「可灵 Kling 图生视频」。

## Capabilities

### New Capabilities
- `ai-video-studio/studio-settings`: 定义短视频工坊设置与系统 AI 能力槽位的继承规则、引擎选择状态机与连通性自测能力。

### Modified Capabilities
<!-- 无现有 spec 发生冲突修改 -->

## Impact

- 涉及文件：
  - `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`: 重构引擎下拉列表、支持 `system-video` 选项与当前配置动态呈现、增加前往 AI 配置弹窗/页面跳转、重构 `_test` 可用性检测分支；
  - `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: 确保 `VideoGenAdapterFactory` 支持根据工坊偏好明确区分 `system-video` 与独立引擎配置；
- 不影响现有本地 Ken Burns 动效生成与可灵生成逻辑，属于完全向后兼容的 UI 与调度衔接升级。
