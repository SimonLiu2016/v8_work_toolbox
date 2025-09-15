#!/bin/bash

# Password Manager Installer Creation Script
# 创建专业安装程序(.exe/.dmg)的脚本

echo "========================================="
echo "  Password Manager Installer Creator     "
echo "========================================="
echo

# 检查操作系统
OS_TYPE=$(uname -s)
echo "检测到的操作系统: $OS_TYPE"
echo

# 获取项目路径 - 修复路径获取逻辑，确保指向项目根目录
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
OUTPUT_DIR="$PROJECT_DIR/build/installer"
mkdir -p "$OUTPUT_DIR"
echo "安装程序输出目录: $OUTPUT_DIR"
echo

# 根据操作系统选择创建安装程序的工具
if [ "$OS_TYPE" = "Darwin" ]; then
    # macOS系统
    echo "创建macOS安装程序..."
    
    # 检查是否安装了create-dmg工具
    if ! command -v create-dmg &> /dev/null; then
        echo "警告: 未安装create-dmg工具，正在尝试安装..."
        if command -v brew &> /dev/null; then
            echo "正在通过Homebrew安装create-dmg..."
            brew install create-dmg
            if [ $? -ne 0 ]; then
                echo "错误: create-dmg安装失败"
                exit 1
            fi
        else
            echo "错误: 未安装Homebrew，无法自动安装create-dmg"
            echo "请手动安装: brew install create-dmg"
            exit 1
        fi
    fi
    
    # 检查是否存在macOS构建产物
    MACOS_BUILD_DIR="$PROJECT_DIR/build/macos/Build/Products/Release"
    if [ ! -d "$MACOS_BUILD_DIR" ]; then
        echo "错误: 未找到macOS构建产物，请先运行构建命令:"
        echo "  flutter build macos --release"
        exit 1
    fi
    
    # 查找.app文件
    MACOS_APP_FILE=$(find "$MACOS_BUILD_DIR" -name "*.app" -type d | head -n 1)
    if [ -z "$MACOS_APP_FILE" ] || [ ! -d "$MACOS_APP_FILE" ]; then
        echo "错误: 未找到macOS .app文件"
        exit 1
    fi
    
    echo "找到macOS应用: $MACOS_APP_FILE"
    
    # 验证应用签名
    echo "验证应用签名..."
    codesign --verify --deep --strict "$MACOS_APP_FILE"
    if [ $? -eq 0 ]; then
        echo "✓ 应用签名验证通过"
    else
        echo "⚠ 警告: 应用签名验证失败，但仍继续创建安装包"
    fi
    
    # 创建DMG安装程序
    MACOS_DMG_NAME="password_manager-macos-$VERSION.dmg"
    echo "创建macOS DMG安装程序: $MACOS_DMG_NAME"
    
    create-dmg \
      --volname "Password Manager" \
      --window-pos 200 120 \
      --window-size 800 400 \
      --icon-size 100 \
      --app-drop-link 600 185 \
      "$OUTPUT_DIR/$MACOS_DMG_NAME" \
      "$MACOS_APP_FILE"
    
    if [ $? -eq 0 ] && [ -f "$OUTPUT_DIR/$MACOS_DMG_NAME" ]; then
        echo "✓ macOS DMG安装程序创建成功: $OUTPUT_DIR/$MACOS_DMG_NAME"
        DMG_SIZE=$(du -h "$OUTPUT_DIR/$MACOS_DMG_NAME" | cut -f1)
        echo "  文件大小: $DMG_SIZE"
    else
        echo "✗ macOS DMG安装程序创建失败"
        exit 1
    fi
    
elif [ "$OS_TYPE" = "Linux" ]; then
    # Linux系统 - 创建简单的安装脚本
    echo "创建Linux安装脚本..."
    
    # 检查是否存在Linux构建产物
    LINUX_BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
    if [ ! -d "$LINUX_BUILD_DIR" ]; then
        echo "错误: 未找到Linux构建产物，请先运行构建命令:"
        echo "  flutter build linux --release"
        exit 1
    fi
    
    # 创建安装脚本
    INSTALL_SCRIPT="$OUTPUT_DIR/install-password-manager.sh"
    cat > "$INSTALL_SCRIPT" << 'EOF'
#!/bin/bash

# Password Manager Linux Installer
# Linux安装脚本

echo "Password Manager Linux 安装程序"
echo "=============================="
echo

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用sudo运行此安装程序:"
    echo "  sudo $0"
    exit 1
fi

# 创建安装目录
INSTALL_DIR="/opt/password_manager"
echo "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 复制文件
echo "复制应用文件..."
cp -r ./bundle/* "$INSTALL_DIR/"

# 创建桌面快捷方式
DESKTOP_FILE="/usr/share/applications/password_manager.desktop"
echo "创建桌面快捷方式..."
cat > "$DESKTOP_FILE" << 'DESKTOP_EOF'
[Desktop Entry]
Name=Password Manager
Comment=Secure password management application
Exec=/opt/password_manager/password_manager
Icon=/opt/password_manager/data/flutter_assets/images/icon.png
Terminal=false
Type=Application
Categories=Utility;Security;
DESKTOP_EOF

# 创建启动脚本
LAUNCH_SCRIPT="/usr/local/bin/password_manager"
echo "创建启动脚本..."
cat > "$LAUNCH_SCRIPT" << 'LAUNCH_EOF'
#!/bin/bash
/opt/password_manager/password_manager "$@"
LAUNCH_EOF

# 设置权限
chmod +x "$LAUNCH_SCRIPT"
chmod +x "$INSTALL_DIR/password_manager"
chmod -R 755 "$INSTALL_DIR"

echo "安装完成！"
echo "您可以通过以下方式启动应用:"
echo "  1. 在应用菜单中找到Password Manager"
echo "  2. 在终端中运行: password_manager"
echo "  3. 运行: /opt/password_manager/password_manager"
EOF

    # 复制Linux构建产物到安装脚本目录
    cp -r "$LINUX_BUILD_DIR" "$OUTPUT_DIR/bundle"
    
    # 设置安装脚本权限
    chmod +x "$INSTALL_SCRIPT"
    
    echo "✓ Linux安装脚本创建成功: $INSTALL_SCRIPT"
    echo "  使用方法:"
    echo "    cd $OUTPUT_DIR"
    echo "    sudo ./install-password-manager.sh"
    
else
    # Windows系统或其他系统
    echo "创建Windows安装程序..."
    
    # 检查是否在Windows环境下运行（通过环境变量判断）
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]]; then
        # Windows环境
        # 检查是否安装了Inno Setup命令行工具
        if ! command -v iscc &> /dev/null; then
            echo "警告: 未找到Inno Setup命令行编译器(iscc)"
            echo "请安装Inno Setup以创建Windows安装程序:"
            echo "  访问: https://jrsoftware.org/isinfo.php"
            echo "  或使用choco安装: choco install innosetup"
            exit 1
        fi
        
        # 检查是否存在Windows构建产物
        WINDOWS_BUILD_DIR="$PROJECT_DIR/build/windows/x64/runner/Release"
        if [ ! -d "$WINDOWS_BUILD_DIR" ]; then
            echo "错误: 未找到Windows构建产物，请先运行构建命令:"
            echo "  flutter build windows --release"
            exit 1
        fi
        
        # 创建Inno Setup脚本
        INNO_SCRIPT="$OUTPUT_DIR/password_manager_installer.iss"
        # 使用相对于项目根目录的正确路径
        # 在GitHub Actions Windows环境中：
        # - 脚本在 build/installer 目录中执行
        # - LICENSE文件在项目根目录
        # - Windows构建产物在 build/windows/x64/runner/Release
        cat > "$INNO_SCRIPT" << EOF
; Password Manager Windows Installer Script
; Inno Setup脚本

#define MyAppName "Password Manager"
#define MyAppVersion "$VERSION"
#define MyAppPublisher "V8EN"
#define MyAppURL "https://v8en.com"
#define MyAppExeName "password_manager.exe"

[Setup]
AppId={{8D2A9E78-7D1A-4E5C-9F3D-2A7D3C8E1F4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

DefaultDirName={autopf}\\{#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\\..\\LICENSE
PrivilegesRequired=admin
OutputDir=.
OutputBaseFilename=password_manager-windows-{#MyAppVersion}-setup
SetupIconFile=..\\..\\windows\\runner\\resources\\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; 由于GitHub Actions环境中可能没有安装中文语言包，暂时只支持英语
; 如果需要添加中文支持，可以在本地环境中取消注释上面一行

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: ..\\..\\build\\windows\\x64\\runner\\Release\\*; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
EOF

        # 编译安装程序
        echo "编译Windows安装程序..."
        iscc "$INNO_SCRIPT"
        
        if [ $? -eq 0 ]; then
            WINDOWS_INSTALLER=$(ls "$OUTPUT_DIR"/password_manager-windows-*.exe 2>/dev/null | head -n 1)
            if [ -n "$WINDOWS_INSTALLER" ] && [ -f "$WINDOWS_INSTALLER" ]; then
                echo "✓ Windows安装程序创建成功: $WINDOWS_INSTALLER"
                EXE_SIZE=$(du -h "$WINDOWS_INSTALLER" | cut -f1)
                echo "  文件大小: $EXE_SIZE"
            else
                echo "✗ Windows安装程序创建失败"
                exit 1
            fi
        else
            echo "✗ Windows安装程序编译失败"
            exit 1
        fi
    else
        echo "警告: 当前环境不支持Windows安装程序创建"
        echo "请在Windows环境下运行此脚本以创建Windows安装程序"
        # 但仍然创建ZIP包作为替代
        WINDOWS_BUILD_DIR="$PROJECT_DIR/build/windows/x64/runner/Release"
        if [ -d "$WINDOWS_BUILD_DIR" ]; then
            WINDOWS_ZIP_NAME="password_manager-windows-$VERSION.zip"
            echo "创建Windows ZIP包: $WINDOWS_ZIP_NAME"
            cd "$WINDOWS_BUILD_DIR"
            zip -r "$OUTPUT_DIR/$WINDOWS_ZIP_NAME" ./* >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "✓ Windows ZIP包创建成功: $OUTPUT_DIR/$WINDOWS_ZIP_NAME"
            else
                echo "⚠ 警告: Windows ZIP包创建失败"
            fi
            cd "$PROJECT_DIR"
        else
            echo "警告: 未找到Windows构建产物"
        fi
    fi
fi

echo
echo "安装程序创建完成！"