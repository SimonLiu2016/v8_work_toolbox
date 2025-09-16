# V8WorkToolbox 应用程序图标替换指南

## 概述

本指南将帮助您为 V8WorkToolbox 应用程序替换默认的 Flutter 图标。

## 准备工作

1. 准备一个高质量的图标图像文件（建议使用 PNG 格式）
2. 推荐尺寸：至少 1024x1024 像素，以确保在所有设备上都有良好的显示效果

## 替换步骤

### 方法一：使用自动脚本（推荐）

1. 确保您有一个高质量的图标文件（例如 `my_icon.png`）

2. 运行图标替换脚本：

   ```bash
   ./replace_app_icon.sh /path/to/your/icon.png
   ```

3. 重新构建应用程序：
   ```bash
   flutter build macos
   ```

### 方法二：手动替换

1. 将您的图标文件重命名为以下名称并替换对应文件：

   - `app_icon_16.png` (16x16)
   - `app_icon_32.png` (32x32)
   - `app_icon_64.png` (64x64)
   - `app_icon_128.png` (128x128)
   - `app_icon_256.png` (256x256)
   - `app_icon_512.png` (512x512)
   - `app_icon_1024.png` (1024x1024)

2. 图标文件位置：

   ```
   macos/Runner/Assets.xcassets/AppIcon.appiconset/
   ```

3. 重新构建应用程序：
   ```bash
   flutter build macos
   ```

## 验证结果

构建完成后，您可以在以下位置找到应用程序并验证图标是否已更新：

- 构建输出：`build/macos/Build/Products/Release/V8WorkToolbox.app`
- 应用程序启动后，程序坞中也会显示新图标

## 注意事项

1. 确保图标文件是正方形的，以避免变形
2. 建议使用透明背景的 PNG 格式图标
3. 替换图标后需要重新构建应用程序才能看到效果
4. 如果图标没有立即更新，可能需要重启程序坞：
   ```bash
   killall Dock
   ```
