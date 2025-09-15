#!/bin/bash

# macOS应用构建脚本
# 支持本地和CI环境中的代码签名

echo "Building macOS app..."

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
  
  # 如果有签名证书设置，则配置签名
  if [[ -n "$MACOS_DEVELOPMENT_TEAM" ]] && [[ -n "$MACOS_SIGNING_CERTIFICATE" ]] && [[ -n "$MACOS_SIGNING_CERTIFICATE_PWD" ]]; then
    echo "Setting up code signing..."
    chmod +x "$SCRIPT_DIR/setup-macos-signing.sh"
    "$SCRIPT_DIR/setup-macos-signing.sh"
    
    # 更新Xcode项目中的开发团队
    sed -i '' "s/DEVELOPMENT_TEAM = \"\"/DEVELOPMENT_TEAM = \"$MACOS_DEVELOPMENT_TEAM\"/g" macos/Runner.xcodeproj/project.pbxproj
    
    # 构建macOS应用（带签名）
    echo "Building macOS app with code signing..."
    flutter build macos --release
  else
    echo "No signing credentials provided, building without code signing"
    # 构建macOS应用（不带签名）
    # 使用build-number参数而不是--no-codesign
    flutter build macos --release --build-number=${GITHUB_RUN_NUMBER:-1}
  fi
else
  echo "Running in local environment"
  # 本地环境构建
  flutter build macos --release
fi

if [ $? -eq 0 ]; then
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
  echo "Error: Failed to build macOS app"
  exit 1
fi

echo "macOS build process completed"