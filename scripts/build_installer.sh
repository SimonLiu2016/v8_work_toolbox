#!/bin/bash

# V8WorkToolbox 应用安装包构建脚本
# 作者: Simon
# 日期: 2025-09-15

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
APP_NAME="V8WorkToolbox"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"

# 显示信息函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Flutter 是否已安装
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter 未安装或未添加到 PATH 中"
        exit 1
    fi
    log_info "Flutter 版本: $(flutter --version | head -n1)"
}

# 检查构建参数
check_args() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 [platform] [build_mode]"
        echo "平台选项: macos, windows, linux, ios, android"
        echo "构建模式: debug, profile, release (默认: release)"
        echo ""
        echo "示例:"
        echo "  $0 macos release"
        echo "  $0 windows release"
        echo "  $0 linux release"
        exit 1
    fi
}

# 构建 macOS 应用
build_macos() {
    local build_mode=$1
    log_info "开始构建 macOS 应用 ($build_mode 模式)"
    
    cd "$PROJECT_DIR"
    flutter build macos --$build_mode
    
    if [ $? -eq 0 ]; then
        log_success "macOS 应用构建成功"
        
        # 创建 DMG 安装包 (如果系统支持)
        if command -v hdiutil &> /dev/null; then
            log_info "创建 DMG 安装包..."
            MACOS_BUILD_DIR="$PROJECT_DIR/build/macos/Build/Products/$([ "$build_mode" = "release" ] && echo "Release" || echo "Debug")"
            APP_PATH="$MACOS_BUILD_DIR/$APP_NAME.app"
            
            if [ -d "$APP_PATH" ]; then
                DMG_NAME="$APP_NAME-macos-$build_mode.dmg"
                DMG_PATH="$DIST_DIR/$DMG_NAME"
                TEMP_DMG_DIR="$BUILD_DIR/temp_dmg"
                
                # 创建分发目录
                mkdir -p "$DIST_DIR"
                
                # 创建临时 DMG 目录
                rm -rf "$TEMP_DMG_DIR"
                mkdir -p "$TEMP_DMG_DIR"
                
                # 复制应用到临时目录
                cp -R "$APP_PATH" "$TEMP_DMG_DIR/"
                
                # 创建应用程序文件夹的符号链接，以便用户可以拖拽安装
                ln -s /Applications "$TEMP_DMG_DIR/Applications"
                
                # 为 DMG 设置自定义布局（如果系统支持）
                if command -v osascript &> /dev/null; then
                    # 创建一个临时的 AppleScript 来设置 DMG 的视觉外观
                    APPLESCRIPT_FILE="$BUILD_DIR/setup_dmg.scpt"
                    cat > "$APPLESCRIPT_FILE" << EOF
                    tell application "Finder"
                        tell disk "$APP_NAME"
                            open
                            set current view of container window to icon view
                            set toolbar visible of container window to false
                            set statusbar visible of container window to false
                            set the bounds of container window to {400, 100, 900, 400}
                            set theViewOptions to the icon view options of container window
                            set arrangement of theViewOptions to not arranged
                            set icon size of theViewOptions to 72
                            set position of item "$APP_NAME.app" of container window to {160, 150}
                            set position of item "Applications" of container window to {400, 150}
                            close
                            open
                            update without registering applications
                            delay 2
                            eject
                        end tell
                    end tell
EOF
                fi
                
                # 创建 DMG
                hdiutil create -srcfolder "$TEMP_DMG_DIR" -volname "$APP_NAME" -format UDZO -fs HFS+ -ov "$DMG_PATH"
                
                # 清理临时目录
                rm -rf "$TEMP_DMG_DIR"
                
                # 如果有 AppleScript 文件，也清理掉
                if [ -f "$APPLESCRIPT_FILE" ]; then
                    rm -f "$APPLESCRIPT_FILE"
                fi
                
                if [ $? -eq 0 ]; then
                    log_success "DMG 安装包创建成功: $DMG_PATH"
                    log_info "DMG 包含拖拽到应用程序文件夹的功能"
                else
                    log_warning "DMG 创建失败，使用原始构建输出"
                fi
            else
                log_warning "应用包不存在: $APP_PATH"
            fi
        fi
    else
        log_error "macOS 应用构建失败"
        exit 1
    fi
}

# 构建 Windows 应用
build_windows() {
    local build_mode=$1
    log_info "开始构建 Windows 应用 ($build_mode 模式)"
    
    cd "$PROJECT_DIR"
    flutter build windows --$build_mode
    
    if [ $? -eq 0 ]; then
        log_success "Windows 应用构建成功"
        
        # 创建安装包 (如果系统支持)
        if [ "$OS" = "Windows_NT" ]; then
            log_info "Windows 环境下无法创建安装包，请手动打包"
        else
            log_info "Windows 构建输出位置: $PROJECT_DIR/build/windows/runner/$([ "$build_mode" = "release" ] && echo "Release" || echo "Debug")"
            
            # 创建 ZIP 分发包
            mkdir -p "$DIST_DIR"
            ZIP_NAME="$APP_NAME-windows-$build_mode.zip"
            ZIP_PATH="$DIST_DIR/$ZIP_NAME"
            
            cd "$PROJECT_DIR/build/windows/runner/$([ "$build_mode" = "release" ] && echo "Release" || echo "Debug")"
            zip -r "$ZIP_PATH" . -x "*.pdb"
            
            if [ $? -eq 0 ]; then
                log_success "Windows ZIP 包创建成功: $ZIP_PATH"
            else
                log_warning "ZIP 包创建失败"
            fi
        fi
    else
        log_error "Windows 应用构建失败"
        exit 1
    fi
}

# 构建 Linux 应用
build_linux() {
    local build_mode=$1
    log_info "开始构建 Linux 应用 ($build_mode 模式)"
    
    cd "$PROJECT_DIR"
    flutter build linux --$build_mode
    
    if [ $? -eq 0 ]; then
        log_success "Linux 应用构建成功"
        
        # 创建 AppImage 或 tar.gz 包
        LINUX_BUILD_DIR="$PROJECT_DIR/build/linux/$([ "$build_mode" = "release" ] && echo "x64/release" || echo "x64/debug")/bundle"
        
        if [ -d "$LINUX_BUILD_DIR" ]; then
            mkdir -p "$DIST_DIR"
            
            # 创建 tar.gz 包
            TAR_NAME="$APP_NAME-linux-$build_mode.tar.gz"
            TAR_PATH="$DIST_DIR/$TAR_NAME"
            
            cd "$PROJECT_DIR/build/linux/$([ "$build_mode" = "release" ] && echo "x64/release" || echo "x64/debug")"
            tar -czf "$TAR_PATH" bundle
            
            if [ $? -eq 0 ]; then
                log_success "Linux tar.gz 包创建成功: $TAR_PATH"
            else
                log_warning "tar.gz 包创建失败"
            fi
        else
            log_warning "Linux 构建输出目录不存在: $LINUX_BUILD_DIR"
        fi
    else
        log_error "Linux 应用构建失败"
        exit 1
    fi
}

# 构建 Android 应用
build_android() {
    local build_mode=$1
    log_info "开始构建 Android 应用 ($build_mode 模式)"
    
    cd "$PROJECT_DIR"
    
    # 构建 APK
    flutter build apk --$build_mode
    
    if [ $? -eq 0 ]; then
        log_success "Android APK 构建成功"
        
        # 构建 AAB (发布版本)
        if [ "$build_mode" = "release" ]; then
            flutter build appbundle --$build_mode
            if [ $? -eq 0 ]; then
                log_success "Android AAB 构建成功"
            else
                log_warning "Android AAB 构建失败"
            fi
        fi
        
        # 复制到分发目录
        mkdir -p "$DIST_DIR"
        APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-$([ "$build_mode" = "release" ] && echo "release" || echo "debug").apk"
        
        if [ -f "$APK_PATH" ]; then
            cp "$APK_PATH" "$DIST_DIR/$APP_NAME-android-$build_mode.apk"
            log_success "APK 已复制到分发目录"
        fi
    else
        log_error "Android 应用构建失败"
        exit 1
    fi
}

# 构建 iOS 应用
build_ios() {
    local build_mode=$1
    log_info "开始构建 iOS 应用 ($build_mode 模式)"
    
    cd "$PROJECT_DIR"
    
    # 检查是否在 macOS 上运行
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_warning "iOS 构建需要在 macOS 上进行，跳过 iOS 构建"
        return
    fi
    
    flutter build ios --$build_mode --no-codesign
    
    if [ $? -eq 0 ]; then
        log_success "iOS 应用构建成功 (未签名)"
    else
        log_error "iOS 应用构建失败"
        exit 1
    fi
}

# 主函数
main() {
    local platform=$1
    local build_mode=${2:-"release"}
    
    log_info "开始构建 $APP_NAME 安装包"
    log_info "目标平台: $platform"
    log_info "构建模式: $build_mode"
    
    # 验证构建模式
    if [[ ! "$build_mode" =~ ^(debug|profile|release)$ ]]; then
        log_error "无效的构建模式: $build_mode"
        exit 1
    fi
    
    # 检查 Flutter
    check_flutter
    
    # 检查平台
    case $platform in
        "macos")
            build_macos "$build_mode"
            ;;
        "windows")
            build_windows "$build_mode"
            ;;
        "linux")
            build_linux "$build_mode"
            ;;
        "android")
            build_android "$build_mode"
            ;;
        "ios")
            build_ios "$build_mode"
            ;;
        *)
            log_error "不支持的平台: $platform"
            exit 1
            ;;
    esac
    
    log_success "安装包构建完成！分发文件位于: $DIST_DIR"
}

# 检查参数并执行主函数
check_args "$@"
main "$@"