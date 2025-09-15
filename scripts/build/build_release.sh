#!/bin/bash

# Password Manager Release Build Script
# 一键打包Windows和macOS版本

echo "========================================="
echo "  Password Manager Release Build Script  "
echo "========================================="
echo

# 检查Flutter环境
echo "检查Flutter环境..."
if ! command -v flutter &> /dev/null
then
    echo "错误: 未找到Flutter命令，请确保Flutter已正确安装并添加到PATH中"
    exit 1
fi

echo "Flutter版本信息:"
flutter --version
echo

# 获取项目路径 - 修正路径获取逻辑，确保指向项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
echo "项目路径: $PROJECT_DIR"
echo

# 进入项目目录
cd "$PROJECT_DIR"

# 检查项目依赖
echo "检查项目依赖..."
if [ ! -f "pubspec.yaml" ]; then
    echo "错误: 未找到pubspec.yaml文件，请确保在正确的项目目录中"
    exit 1
fi

# 获取版本信息
VERSION=$(grep "version:" pubspec.yaml | cut -d ':' -f 2 | tr -d ' ')
if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi
echo "项目版本: $VERSION"
echo

# 创建输出目录
OUTPUT_DIR="$PROJECT_DIR/build/release"
mkdir -p "$OUTPUT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo

# 安装依赖
echo "安装项目依赖..."
flutter pub get
echo

# 运行代码分析
echo "运行代码分析..."
flutter analyze
if [ $? -ne 0 ]; then
    echo "警告: 代码分析发现问题，但仍继续构建..."
    echo
fi

# 构建Windows版本
echo "开始构建Windows版本..."
echo "------------------------"
BUILD_START_TIME=$(date +%s)

flutter build windows --release

if [ $? -eq 0 ]; then
    BUILD_END_TIME=$(date +%s)
    BUILD_DURATION=$((BUILD_END_TIME-BUILD_START_TIME))
    
    # Windows构建成功
    echo "✓ Windows版本构建成功 (耗时: ${BUILD_DURATION}秒)"
    
    # 查找Windows构建文件
    WINDOWS_BUILD_DIR="$PROJECT_DIR/build/windows/x64/runner/Release"
    if [ -d "$WINDOWS_BUILD_DIR" ]; then
        # 创建Windows压缩包
        WINDOWS_ZIP_NAME="password_manager-windows-$VERSION.zip"
        echo "创建Windows安装包: $WINDOWS_ZIP_NAME"
        
        # 进入Windows构建目录并创建压缩包
        cd "$WINDOWS_BUILD_DIR"
        zip -r "$OUTPUT_DIR/$WINDOWS_ZIP_NAME" ./* >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✓ Windows安装包创建成功: $OUTPUT_DIR/$WINDOWS_ZIP_NAME"
            WINDOWS_SIZE=$(du -h "$OUTPUT_DIR/$WINDOWS_ZIP_NAME" | cut -f1)
            echo "  文件大小: $WINDOWS_SIZE"
        else
            echo "⚠ 警告: Windows安装包创建失败"
        fi
    else
        echo "⚠ 警告: 未找到Windows构建输出目录"
        echo "  尝试查找其他可能的输出位置..."
        # 查找其他可能的Windows构建目录
        WINDOWS_ALT_DIR=$(find "$PROJECT_DIR/build" -type d -path "*/windows/*/runner/Release" 2>/dev/null | head -n 1)
        if [ -n "$WINDOWS_ALT_DIR" ] && [ -d "$WINDOWS_ALT_DIR" ]; then
            echo "  在替代位置找到Windows构建目录: $WINDOWS_ALT_DIR"
            cd "$WINDOWS_ALT_DIR"
            zip -r "$OUTPUT_DIR/$WINDOWS_ZIP_NAME" ./* >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "✓ Windows安装包创建成功: $OUTPUT_DIR/$WINDOWS_ZIP_NAME"
                WINDOWS_SIZE=$(du -h "$OUTPUT_DIR/$WINDOWS_ZIP_NAME" | cut -f1)
                echo "  文件大小: $WINDOWS_SIZE"
            else
                echo "⚠ 警告: Windows安装包创建失败"
            fi
        else
            echo "  未在替代位置找到Windows构建目录"
        fi
    fi
else
    echo "✗ Windows版本构建失败"
    echo "  可能的原因:"
    echo "  1. 未启用Windows桌面平台支持"
    echo "  2. 缺少Windows构建工具"
    echo "  3. 项目配置问题"
fi

echo
cd "$PROJECT_DIR"

# 构建macOS版本
echo "开始构建macOS版本..."
echo "-----------------------"
BUILD_START_TIME=$(date +%s)

flutter build macos --release

if [ $? -eq 0 ]; then
    BUILD_END_TIME=$(date +%s)
    BUILD_DURATION=$((BUILD_END_TIME-BUILD_START_TIME))
    
    # macOS构建成功
    echo "✓ macOS版本构建成功 (耗时: ${BUILD_DURATION}秒)"
    
    # 查找macOS构建文件
    MACOS_BUILD_DIR="$PROJECT_DIR/build/macos/Build/Products/Release"
    if [ -d "$MACOS_BUILD_DIR" ]; then
        # 检查是否存在.app文件
        MACOS_APP_FILE=$(find "$MACOS_BUILD_DIR" -name "*.app" -type d | head -n 1)
        if [ -n "$MACOS_APP_FILE" ] && [ -d "$MACOS_APP_FILE" ]; then
            # 创建macOS .dmg安装包
            MACOS_DMG_NAME="password_manager-macos-$VERSION.dmg"
            echo "创建macOS安装包: $MACOS_DMG_NAME"
            
            # 先创建ZIP文件作为临时方案
            cd "$MACOS_BUILD_DIR"
            zip -r "$OUTPUT_DIR/password_manager-macos-$VERSION.zip" ./* >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo "✓ macOS ZIP包创建成功: $OUTPUT_DIR/password_manager-macos-$VERSION.zip"
                MACOS_SIZE=$(du -h "$OUTPUT_DIR/password_manager-macos-$VERSION.zip" | cut -f1)
                echo "  文件大小: $MACOS_SIZE"
                
                # 如果系统安装了create-dmg工具，则创建.dmg文件
                if command -v create-dmg &> /dev/null; then
                    echo "  正在创建.dmg安装包..."
                    create-dmg \
                      --volname "Password Manager" \
                      --window-pos 200 120 \
                      --window-size 800 400 \
                      --icon-size 100 \
                      --app-drop-link 600 185 \
                      "$OUTPUT_DIR/$MACOS_DMG_NAME" \
                      "$MACOS_APP_FILE" >/dev/null 2>&1
                    
                    if [ $? -eq 0 ] && [ -f "$OUTPUT_DIR/$MACOS_DMG_NAME" ]; then
                        echo "✓ macOS DMG安装包创建成功: $OUTPUT_DIR/$MACOS_DMG_NAME"
                        DMG_SIZE=$(du -h "$OUTPUT_DIR/$MACOS_DMG_NAME" | cut -f1)
                        echo "  文件大小: $DMG_SIZE"
                    else
                        echo "⚠ 警告: macOS DMG安装包创建失败，仅提供ZIP包"
                    fi
                else
                    echo "  系统未安装create-dmg工具，仅提供ZIP包"
                    echo "  如需创建.dmg安装包，请安装create-dmg工具:"
                    echo "  brew install create-dmg"
                fi
            else
                echo "⚠ 警告: macOS ZIP包创建失败"
            fi
        else
            echo "⚠ 警告: 未找到macOS .app文件"
        fi
    else
        echo "⚠ 警告: 未找到macOS构建输出目录"
    fi
else
    echo "✗ macOS版本构建失败"
fi

echo
cd "$PROJECT_DIR"

# 显示构建结果
echo "========================================="
echo "           构建完成摘要                  "
echo "========================================="

# 列出所有生成的文件
if [ -d "$OUTPUT_DIR" ]; then
    echo "生成的安装包:"
    ls -lh "$OUTPUT_DIR" | grep -E "\.(zip|dmg|exe|msi)" | awk '{print "  " $5 "  " $9}'
    
    if [ $(ls -1 "$OUTPUT_DIR" | grep -E "\.(zip|dmg|exe|msi)" | wc -l) -eq 0 ]; then
        echo "  未找到生成的安装包文件"
    fi
else
    echo "输出目录不存在"
fi

echo
echo "构建日志已保存到: $OUTPUT_DIR/build.log"
echo
echo "如需创建安装程序(.exe/.msi/.dmg)，请使用相应的打包工具处理生成的文件。"
echo
echo "说明:"
echo "1. Windows版本生成为ZIP压缩包，解压后可直接运行"
echo "2. macOS版本生成为ZIP压缩包和.dmg安装包(如果系统支持)"
echo "3. 如需创建标准安装程序，请使用专业打包工具"
echo

echo "脚本执行完成！"