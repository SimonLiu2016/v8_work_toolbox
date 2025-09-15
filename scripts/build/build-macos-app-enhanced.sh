#!/bin/bash

# 增强版macOS应用构建脚本
# 支持本地和CI环境中的代码签名

echo "Building macOS app (enhanced version)..."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

cd "$PROJECT_ROOT" || exit 1

# 清理之前的构建
echo "Cleaning previous builds..."
flutter clean
flutter pub get

# 检查是否在CI环境中
if [[ -n "$CI" ]]; then
  echo "Running in CI environment"
  
  # 如果有签名证书和配置文件设置，则配置签名
  if [[ -n "$MACOS_DEVELOPMENT_TEAM" ]] && [[ -n "$MACOS_SIGNING_CERTIFICATE" ]] && [[ -n "$MACOS_SIGNING_CERTIFICATE_PWD" ]] && [[ -n "$MACOS_PROVISIONING_PROFILE" ]]; then
    echo "Setting up code signing with provisioning profile..."
    chmod +x "$SCRIPT_DIR/setup-macos-signing.sh"
    "$SCRIPT_DIR/setup-macos-signing.sh"
    
    # 更新Xcode项目中的开发团队
    echo "Updating Xcode project with development team..."
    sed -i '' "s/DEVELOPMENT_TEAM = \"[^\"]*\"/DEVELOPMENT_TEAM = \"$MACOS_DEVELOPMENT_TEAM\"/g" macos/Runner.xcodeproj/project.pbxproj
    
    # 使用手动签名并指定您的配置文件
    echo "Setting manual code signing with your provisioning profile..."
    sed -i '' 's/CODE_SIGN_IDENTITY = "-"/CODE_SIGN_IDENTITY = "Apple Distribution"/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g' macos/Runner.xcodeproj/project.pbxproj
    
    # 设置您的特定配置文件
    echo "Setting your specific provisioning profile: V8en Password Manager Profile"
    sed -i '' 's/PROVISIONING_PROFILE_SPECIFIER = ""/PROVISIONING_PROFILE_SPECIFIER = "V8en Password Manager Profile"/g' macos/Runner.xcodeproj/project.pbxproj
    
    # 构建macOS应用（带签名）
    echo "Building macOS app with code signing..."
    flutter build macos --release --build-number=${GITHUB_RUN_NUMBER:-1} -v
  else
    echo "No signing credentials provided, building without code signing"
    
    # 禁用Xcode项目中的代码签名
    echo "Disabling code signing in Xcode project..."
    # Debug配置
    sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Development"/CODE_SIGN_IDENTITY = "-"/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/DEVELOPMENT_TEAM = "[^"]*"/DEVELOPMENT_TEAM = ""/g' macos/Runner.xcodeproj/project.pbxproj
    # Release配置
    sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Distribution"/CODE_SIGN_IDENTITY = "-"/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/DEVELOPMENT_TEAM = "[^"]*"/DEVELOPMENT_TEAM = ""/g' macos/Runner.xcodeproj/project.pbxproj
    # Profile配置
    sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Development"/CODE_SIGN_IDENTITY = "-"/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g' macos/Runner.xcodeproj/project.pbxproj
    sed -i '' 's/DEVELOPMENT_TEAM = "[^"]*"/DEVELOPMENT_TEAM = ""/g' macos/Runner.xcodeproj/project.pbxproj
    
    # 构建macOS应用（不带签名）
    echo "Building macOS app without code signing..."
    flutter build macos --release --build-number=${GITHUB_RUN_NUMBER:-1} -v
  fi
else
  echo "Running in local environment"
  # 本地环境构建
  flutter build macos --release -v
fi

BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ]; then
  echo "macOS app built successfully"
  
  # 查找构建的应用
  MACOS_BUILD_DIR="build/macos/Build/Products/Release"
  if [ -d "$MACOS_BUILD_DIR" ]; then
    MACOS_APP_FILE=$(find "$MACOS_BUILD_DIR" -name "*.app" -type d | head -n 1)
    if [ -n "$MACOS_APP_FILE" ] && [ -d "$MACOS_APP_FILE" ]; then
      echo "Found built app: $MACOS_APP_FILE"
      
      # 验证应用签名（如果在CI环境中且有签名设置）
      if [[ -n "$CI" ]] && [[ -n "$MACOS_DEVELOPMENT_TEAM" ]]; then
        echo "Verifying app signature..."
        codesign --verify --deep --strict "$MACOS_APP_FILE"
        if [ $? -eq 0 ]; then
          echo "App signature verified successfully"
        else
          echo "Warning: App signature verification failed"
        fi
      fi
    else
      echo "Warning: Could not find built .app file"
    fi
  else
    echo "Warning: Could not find build directory"
  fi
else
  echo "Error: Failed to build macOS app (exit code: $BUILD_RESULT)"
  
  # 提供一些调试信息
  echo "Flutter version:"
  flutter --version
  
  echo "Available Flutter build options:"
  flutter build macos -h
  
  exit 1
fi

echo "macOS build process completed"