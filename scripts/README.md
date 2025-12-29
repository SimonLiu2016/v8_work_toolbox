# 脚本说明

此目录包含项目相关的自动化脚本。

## 脚本列表

### build_installer.sh
构建 V8WorkToolbox 应用安装包的脚本。

**功能：**
- 支持多平台构建 (macOS, Windows, Linux, Android, iOS)
- 支持多种构建模式 (debug, profile, release)
- 自动创建分发包 (DMG, ZIP, tar.gz, APK)
- macOS DMG 包含拖拽到应用程序文件夹的安装功能

**使用方法：**
```bash
# 构建 macOS 版本 (发布模式)
./scripts/build_installer.sh macos release

# 构建 Windows 版本 (发布模式)
./scripts/build_installer.sh windows release

# 构建 Linux 版本 (发布模式)
./scripts/build_installer.sh linux release

# 构建 Android 版本 (发布模式)
./scripts/build_installer.sh android release

# 构建 iOS 版本 (发布模式)
./scripts/build_installer.sh ios release
```

### bc_config_tool.sh
Beyond Compare 配置修改工具。

**功能：**
- 删除 BCState.xml 中的 CheckID 和 LastChecked 标签
- 删除 BCSessions.xml 中的 Flags 属性
- 自动备份原文件

### fix_bc_config.sh
Beyond Compare 配置修复脚本。

**功能：**
- 修复 Beyond Compare 试用期问题
- 自动备份配置文件

### modify_bc_config.sh
Beyond Compare 配置修改脚本。

**功能：**
- 修改 Beyond Compare 配置文件
- 自动启动 Beyond Compare

### push_codes.sh
代码推送脚本。

**功能：**
- 自动推送代码到远程仓库