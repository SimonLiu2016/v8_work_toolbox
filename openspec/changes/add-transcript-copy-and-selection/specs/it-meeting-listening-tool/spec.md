## ADDED Requirements

### Requirement: Transcript Text Selection
精听文稿抽屉（TranscriptDrawer）中的正文内容必须支持鼠标自由划选、双击选词与系统原生复制菜单，且划选操作不得误触发音频跳转播放。

#### Scenario: User selects words in standard transcript
- **WHEN** 用户在“标准原文”视图中使用鼠标光标拖选文本或双击选中某个单词
- **THEN** 系统展示选中文本高亮与原生右键操作菜单，允许复制选中的文本内容，且当前播放进度不发生跳转

#### Scenario: User selects words in sense group transcript
- **WHEN** 用户在“意群断句”视图中使用鼠标划选单个意群或跨行文本
- **THEN** 系统正常保持文本选取状态并支持复制，且不会触发播放器跳播

### Requirement: Quick Copy Action for Turn Text
精听文稿每个发言轮次的工具栏中必须提供一键快速复制按钮（`📋`），支持将当前发言文本写入剪贴板并给出提示反馈。

#### Scenario: Quick copy pure English in standard view
- **WHEN** 用户在“标准原文”视图中点击某发言条目的复制按钮（`📋`）
- **THEN** 系统将该条目的完整纯英文文本（不包含发言人姓名或时间戳前缀）写入系统剪贴板，并展示“已复制”提示反馈

#### Scenario: Quick copy formatted sense groups in sense group view
- **WHEN** 用户在“意群断句”视图中点击某发言条目的复制按钮（`📋`）
- **THEN** 系统将按照多行编号及 `//` 呼吸停顿符排版的意群文本写入系统剪贴板，方便用户直接粘贴至外部 AI 工具进行合理性评估
