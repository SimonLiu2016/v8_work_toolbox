## Context

参见 `proposal.md`。系统全局已建立 `AiConfigStore` 统一托管模型供应商与能力槽位（包括 `video` 槽位与 SenseAudio），且 `VideoGenAdapterFactory` 底层支持调度该模型。然而，短视频工坊的设置界面 [`StudioSettingsDialog`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/ui/studio_settings_dialog.dart) 仍停留在早期的写死配置状态，仅提供本地 Ken Burns 与独立可灵选项，导致用户在全局配置 SenseAudio 后无法在工坊设置中直观看到和应用。

## Goals / Non-Goals

**Goals:**
- 在工坊设置的视频生成引擎中引入 `system-video`（跟随系统全局 AI 视频配置），并作为默认推荐选项；
- 动态读取并呈现全局绑定的视频模型信息（例如：`SenseAudio - doubao-seedance-2-0-260128`），清晰告知密钥已安全托管；
- 在工坊设置中提供「前往 AI 基础设施配置」快速通道，方便随时调整系统模型参数；
- 实现工坊内一键「测试可用性」，能够直接校验全局配置的视频模型（SenseAudio）连通性与 Key 状态；
- 保留切换到本地 Ken Burns（FFmpeg）或独立可灵的灵活性。

**Non-Goals:**
- 不改变全局 `AiConfigStore` 的配置与持久化存储协议；
- 不废弃本地 Ken Burns 动效引擎。

## Decisions

### D1: 统一虚拟引擎 ID `system-video` 作为工坊默认配置
- **选择**: 在 `StudioSettingsDialog` 中引入 `system-video` 作为视频能力项的首选 engineId。若用户未显式修改为其他独立引擎，默认即为 `system-video`。
- **备选方案**: 直接把各个供应商（如 `senseaudio-xxx`）平铺在工坊设置的下拉列表中。
  - *否决原因*: 这会导致工坊设置与系统 AI 配置职责重叠，用户每次在全局更换模型还要来工坊重复选择；采用“跟随系统配置”能够一次配置、全局生效，最为省心。

### D2: 状态与密钥展示解耦
- **选择**: 当选中 `system-video` 时，隐藏原有的明文 API Key 文本框，替换为安全状态提示（“密钥已由系统 Keychain 安全托管”）以及直达「AI 基础设施配置」的弹窗/页面按钮。
- **备选方案**: 在工坊设置里允许直接修改系统级密钥。
  - *否决原因*: 破坏系统密钥管理的一致性，容易产生数据竞态。

### D3: 测试可用性复用 Adapter 探测
- **选择**: 在工坊设置中点击「测试可用性」时，直接通过 `VideoGenAdapterFactory.create(preferredEngineId: selectedEngineId)` 获取对应的适配器，调用 `isAvailable()` 或预检方法进行探测。
- **效果**: SenseAudio、Kling 和本地 FFmpeg 各自执行针对性的有效性验证，保证结果准确。

## Risks / Trade-offs

- **[系统未配置视频模型时的降级提示]** → 当系统 `video` 槽位为空时，下拉列表显示为「🌟 跟随系统配置 (未绑定视频模型)」，点击测试或生成时明确提示并引导跳转配置页面。
