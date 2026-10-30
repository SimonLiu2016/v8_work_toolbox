## Why

在短视频工坊的场景库中，用户在全景母图与各机位视图中进行生图操作时，发现了三处严重的 UI 渲染崩溃与排版缺陷：
1. 点击“预览Prompt”按钮打开的对话框是一片灰色且无任何内容（因 `AlertDialog.actions` 内部直接放置了 `Spacer()`，导致在 Release 模式下触发 Flutter 的 `ParentDataWidget` 致命异常并展示默认灰色错误占位）。
2. “生成 360° 全景母图”按钮前置了多余图标/emoji，文案包含多余的“（1 次 API）”，造成界面噪点与冗余感。
3. 后置的“一键无损切片”按钮同样包含多余图标/emoji，且由于操作栏单行排布过长，导致该按钮严重溢出到视口窗口之外无法完整显示。

修复这些问题以恢复 Prompt 预览微调功能的正常运作，并优化全景母图操作栏的视觉整洁度与响应式自适应布局。

## What Changes

- **修复 `AssetPromptPreviewDialog` 渲染崩溃**：重构弹窗底部的操作栏排版，移除在 `OverflowBar` 内非法的 `Spacer()`，改为在合法 `Row` 容器内管理两端对齐或自适应排列，确保在 Release 环境下平稳渲染，完整展示提示词层级与编辑输入区。
- **净化全景母图与切片操作按钮**：
  - 移除“生成 360° 全景母图”按钮中的重复 emoji/图标，精简文案去除“（1 次 API）”，简化为纯粹清晰的“生成全景母图”或“生成 360° 全景母图”。
  - 移除“一键无损切片”按钮中的重复 emoji/图标，精简文案为“一键切片视角”或“一键无损切片”。
- **重构全景母图操作栏响应式布局，根除溢出**：
  - 将冗长的全景切片原理说明文本下移为副标题或辅助说明文本。
  - 右侧操作按钮区域引入 `Wrap` 或弹性排列，确保在任意窗口宽度或弹窗分栏宽度下，三个按钮绝不溢出可视窗口。

## Capabilities

### Modified Capabilities
- `ai-video-studio/scene-360-panorama-projection`: 完善场景全景母图生成与切片交互规范，确保操作按钮无冗余视觉干扰、布局严密防溢出，且提示词预览与实时微调弹窗在各运行环境下稳定渲染。

## Impact

- `lib/tools/ai_video_studio/ui/asset_prompt_preview_dialog.dart`: 修复 `actions` 底部按钮栏布局结构，消除 `_OverflowBarParentData` 异常。
- `lib/tools/ai_video_studio/ui/series_page.dart`: 优化场景编辑弹窗中全景母图区域的标题、说明文本与操作按钮布局，消除横向溢出并精炼文案。
- 相关单元与 Widget 测试：更新/补充 `asset_prompt_preview_dialog_test.dart` 确保弹窗无异常渲染。
