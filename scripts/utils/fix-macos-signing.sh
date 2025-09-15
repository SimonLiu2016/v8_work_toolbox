#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🔍 当前项目根目录: $PROJECT_ROOT"

# 步骤1: 检查并安装开发证书
echo "🔍 检查Apple Developer证书..."
if ! security find-identity -v -p codesigning | grep -q "Apple Development"; then
  echo "⚠️ 未找到开发证书，正在启动Xcode创建证书流程..."
  open -a Xcode
  echo "请在Xcode中选择: Xcode菜单 > Preferences > Accounts > + > 添加Apple ID"
  echo "添加后选择Manage Certificates > + > Apple Development"
  read -p "创建完成后按回车键继续..."
else
  echo "✅ 已找到开发证书"
fi

# 步骤2: 验证Flutter项目结构
echo "🔍 验证Flutter项目结构..."
if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
  echo "❌ 错误: 在 $PROJECT_ROOT 目录下未找到 pubspec.yaml 文件"
  echo "请确保此脚本位于Flutter项目的根目录中"
  exit 1
fi

if [ ! -d "$PROJECT_ROOT/macos" ]; then
  echo "❌ 错误: 在 $PROJECT_ROOT 目录下未找到 macos 目录"
  echo "此项目可能不支持macOS平台，或者结构不完整"
  exit 1
fi

# 步骤3: 配置Flutter macOS项目自动签名
echo "🔧 配置Flutter macOS项目自动签名..."
cd "$PROJECT_ROOT" || exit
flutter clean

cd macos || exit

# 修改macOS项目的Runner.xcodeproj配置
# 使用PlistBuddy修改Info.plist
if [ -f "Runner/Info.plist" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.v8en.passwordManager" Runner/Info.plist
  echo "✅ 已设置Bundle Identifier为 com.v8en.passwordManager"
else
  echo "❌ 错误: 未找到 Runner/Info.plist 文件"
  exit 1
fi

# 启用自动签名 (需要Xcode 12+)
echo "🚀 执行 xcodebuild 启用自动签名..."
xcodebuild -project Runner.xcodeproj -allowProvisioningUpdates -alltargets

# 步骤4: 重新获取依赖并构建
echo "🚀 重新获取依赖并尝试构建..."
cd "$PROJECT_ROOT" || exit
flutter pub get
flutter build macos --debug