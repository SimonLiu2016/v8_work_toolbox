# 脚本说明

此目录包含项目相关的自动化脚本。

## 脚本列表

### deploy_local.sh
**本地 macOS 一键部署脚本**——本机构建并替换 `/Applications` 下的应用。

一条命令完成：清理构建产物 → release 构建 → 注入 mihomo 二进制 → 重新
ad-hoc 签名 → SIGTERM 优雅退出旧实例 → 替换 → 签名与 AOT 快照校验 → 启动。

任一步失败即整体中止，不留下半部署状态。

**功能：**
- `flutter clean` 规避增量构建残留失效 seal（该问题会导致 macOS 拒绝访问 Keychain，进而使 DEK 走文件兜底、旧密文全部解不开）
- 自动从「上一版已部署 bundle」取回 mihomo（它在 `.gitignore`，构建系统不产出它）
- 注入后重新 ad-hoc 签名（往已签名 bundle 加文件会破坏 seal）
- 部署目标路径防呆断言，绝不误删
- 部署前后比对 Dart AOT 快照 md5，确认代码真的更新了
- 优雅退出 + 孤儿 mihomo 兜底清理（精确匹配本应用路径，不误杀 Clash Verge）

**使用方法：**
```bash
# 完整部署
./scripts/deploy_local.sh

# 跳过 clean（仅调试用，有 seal 失效风险）
./scripts/deploy_local.sh --skip-clean
```

> 注：本脚本不产出安装包。需要分发包（DMG/ZIP）时用 `build_installer.sh`。

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