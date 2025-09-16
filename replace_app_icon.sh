#!/bin/bash

# V8WorkToolbox 图标替换脚本
# 使用方法: ./replace_app_icon.sh /path/to/your/icon.png

if [ $# -eq 0 ]; then
    echo "请提供图标文件路径"
    echo "使用方法: ./replace_app_icon.sh /path/to/your/icon.png"
    exit 1
fi

ICON_PATH="$1"

if [ ! -f "$ICON_PATH" ]; then
    echo "错误: 图标文件不存在: $ICON_PATH"
    exit 1
fi

# 检查是否安装了 sips 命令（macOS 自带的图像处理工具）
if ! command -v sips &> /dev/null; then
    echo "错误: 未找到 sips 命令，请在 macOS 上运行此脚本"
    exit 1
fi

# 图标文件目录
ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"

echo "正在为 V8WorkToolbox 应用程序替换图标..."

# 创建不同尺寸的图标
echo "正在生成不同尺寸的图标..."
sips -z 16 16 "$ICON_PATH" --out "$ICON_DIR/app_icon_16.png" > /dev/null 2>&1
sips -z 32 32 "$ICON_PATH" --out "$ICON_DIR/app_icon_32.png" > /dev/null 2>&1
sips -z 64 64 "$ICON_PATH" --out "$ICON_DIR/app_icon_64.png" > /dev/null 2>&1
sips -z 128 128 "$ICON_PATH" --out "$ICON_DIR/app_icon_128.png" > /dev/null 2>&1
sips -z 256 256 "$ICON_PATH" --out "$ICON_DIR/app_icon_256.png" > /dev/null 2>&1
sips -z 512 512 "$ICON_PATH" --out "$ICON_DIR/app_icon_512.png" > /dev/null 2>&1
sips -z 1024 1024 "$ICON_PATH" --out "$ICON_DIR/app_icon_1024.png" > /dev/null 2>&1

echo "图标替换完成！"
echo "请重新构建应用程序以查看新图标:"
echo "  flutter build macos"