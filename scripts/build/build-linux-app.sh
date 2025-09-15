#!/bin/bash

# Linux应用构建脚本

echo "Building Linux app..."

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
  
  # 在CI环境中安装必要的依赖
  echo "Installing Linux dependencies..."
  sudo apt update
  sudo apt install -y libsecret-1-dev
else
  echo "Running in local environment"
  
  # 检查本地是否安装了必要的依赖
  if ! dpkg -l | grep -q libsecret-1-dev; then
    echo "Warning: libsecret-1-dev is not installed. You may need to install it:"
    echo "sudo apt install libsecret-1-dev"
  fi
fi

# 构建Linux应用
echo "Building Linux app..."
flutter build linux --release

if [ $? -eq 0 ]; then
  echo "Linux app built successfully"
  
  # 查找构建的应用
  LINUX_BUILD_DIR="build/linux/x64/release/bundle"
  if [ -d "$LINUX_BUILD_DIR" ]; then
    echo "Found built app in: $LINUX_BUILD_DIR"
  else
    echo "Warning: Could not find build directory"
  fi
else
  echo "Error: Failed to build Linux app"
  exit 1
fi

echo "Linux build process completed"