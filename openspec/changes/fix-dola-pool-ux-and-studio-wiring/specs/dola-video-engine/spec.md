## ADDED Requirements

### Requirement: Studio Engine Selection Persistence
系统 SHALL 持久化存储用户在工坊设置对话框中选择的图像生成与视频生成引擎偏好。

#### Scenario: Reopening studio settings dialog
- **WHEN** 用户在工坊设置中将视频引擎从跟随系统切换为 Dola 免费号池并关闭弹窗
- **THEN** 再次打开该设置弹窗或重新进入分镜看板时，选中的引擎依然为 Dola 免费号池

### Requirement: Storyboard Keyframe Prerequisite Validation
系统 SHALL 在分镜看板触发视频生成前校验是否已存在关键帧首图，无首图时弹出友好提示而非静默崩溃。

#### Scenario: Click video on shot without keyframe
- **WHEN** 用户在尚未生成关键帧的分镜卡片上点击「视频」按钮
- **THEN** 系统阻止任务排队并弹出指引提示“请先点击关键帧生成首帧画面”

### Requirement: Selectable and Copyable Error Dialog
系统 SHALL 以可选中文字、自动限制最大高度、并提供一键复制按钮的方式展示失败任务的详细报错。

#### Scenario: Viewing task error details
- **WHEN** 视频任务失败并展示错误信息
- **THEN** 错误文本支持完整滚动、选中文本与一键复制全部报错日志，不发生溢出异常
