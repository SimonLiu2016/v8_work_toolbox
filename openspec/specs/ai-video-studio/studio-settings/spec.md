# ai-video-studio/studio-settings Specification

## Purpose
定义短视频工坊（AI Video Studio）工坊设置与系统全局 AI 基础设施能力槽位的继承规则、引擎选项动态映射与可用性连通性测试标准。
## Requirements
### Requirement: 继承系统全局视频模型配置
短视频工坊设置对话框中的视频生成引擎下拉选项 SHALL 包含「跟随系统 AI 配置」，并作为默认选中的首选引擎选项。

#### Scenario: 系统已配置 SenseAudio 视频模型时展示动态标签
- **WHEN** 用户在全局「AI能力配置」中为 `video` 槽位绑定了 SenseAudio 供应商与模型（如 `doubao-seedance-2-0-260128`）
- **THEN** 工坊设置的视频引擎选项显示为「🌟 跟随系统配置 (SenseAudio - doubao-seedance-2-0-260128)」
- **AND** 隐藏手动输入 API Key 输入框，提示「API Key 已由系统全局密钥库统一安全托管」
- **AND** 提供「前往系统 AI 配置」快捷入口按钮

#### Scenario: 系统未绑定任何视频模型候选时的友好提示
- **WHEN** 全局「AI能力配置」中的 `video` 槽位候选列表为空
- **THEN** 引擎标签显示为「🌟 跟随系统配置 (未绑定视频模型)」
- **AND** 提示用户前往全局配置中添加视频模型

### Requirement: 工坊内引擎连通性与可用性自测
工坊设置中的「测试可用性」按钮 SHALL 根据用户当前选中的引擎类型执行对应的可用性探测与有效性校验。

#### Scenario: 测试跟随系统的视频模型连通性
- **WHEN** 用户在视频生成引擎中选择「跟随系统配置」并点击「测试可用性」
- **THEN** 系统读取当前全局绑定的供应商配置与加密存储的密钥
- **AND** 若密钥存在且格式有效，界面展示「通过」绿色指示
- **AND** 若未配置密钥或网络探测不可达，界面展示「失败」红色指示并允许点击直达系统配置进行补全

### Requirement: 保持独立引擎选择的灵活性
工坊设置 SHALL 允许用户显式脱离系统全局配置，选择「本地 Ken Burns（免费）」或「可灵 Kling 图生视频（独立配置）」。

#### Scenario: 用户切换至本地 Ken Burns 免费动效引擎
- **WHEN** 用户在工坊设置下拉框中选择「本地 Ken Burns（免费）」
- **THEN** 引擎选择持久化为本地模式
- **AND** 隐藏 API Key 输入框，点击测试可用性时校验本机 FFmpeg 是否就绪

