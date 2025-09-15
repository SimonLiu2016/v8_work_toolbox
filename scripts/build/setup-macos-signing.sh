#!/bin/bash

# macOS代码签名设置脚本
# 用于在GitHub Actions环境中设置代码签名

echo "Setting up macOS code signing..."

# 检查是否在GitHub Actions环境中
if [[ -z "$CI" ]]; then
  echo "Not running in CI environment. Skipping code signing setup."
  exit 0
fi

# 检查必要的环境变量
if [[ -z "$MACOS_DEVELOPMENT_TEAM" ]] || [[ -z "$MACOS_SIGNING_CERTIFICATE" ]] || [[ -z "$MACOS_SIGNING_CERTIFICATE_PWD" ]] || [[ -z "$MACOS_PROVISIONING_PROFILE" ]]; then
  echo "Missing required environment variables for code signing."
  echo "Please set MACOS_DEVELOPMENT_TEAM, MACOS_SIGNING_CERTIFICATE, MACOS_SIGNING_CERTIFICATE_PWD, and MACOS_PROVISIONING_PROFILE."
  exit 1
fi

# 创建临时密钥链
echo "Creating temporary keychain..."
security create-keychain -p "temporary" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "temporary" build.keychain
security set-keychain-settings -t 3600 -u build.keychain

# 解码并导入证书
echo "Importing signing certificate..."
echo $MACOS_SIGNING_CERTIFICATE | base64 --decode > certificate.p12
security import certificate.p12 -k build.keychain -P $MACOS_SIGNING_CERTIFICATE_PWD -T /usr/bin/codesign
rm -rf certificate.p12

# 解码并保存配置文件（但不直接导入，让Xcode自动处理）
echo "Saving provisioning profile for Xcode to use..."
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
echo $MACOS_PROVISIONING_PROFILE | base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/password_manager.provisionprofile

# 设置钥匙链权限
security set-key-partition-list -S apple-tool:,apple: -s -k "temporary" build.keychain

# 验证证书导入
echo "Verifying certificate..."
security find-identity -v -p codesigning build.keychain

echo "macOS code signing setup completed."