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

### release.sh
**一键版本发布与远程备份脚本**——自动化全量工作区提交、语义化版本升级、分支合并、Git Tag 附注与远程推送。

主要目的：防止本地代码被覆盖或遗漏，确保所有修改 100% 同步备份至 GitHub 远程仓库，并结构化记录版本与 Release Notes。

**功能：**
- **防丢失提交**：自动检测工作区未暂存/未跟踪文件，全量 `git add -A` 并提交，绝不遗漏新文件
- **分支与合并**：支持从当前特性分支一键安全合并入 `main` 后发布
- **智能网络/代理探测**：直连与代理自动 fallback（支持 `~/.proxy_profile` 及 7890/7897/6160 等常用代理端口）
- **版本号自动化**：自动读取与更新 `pubspec.yaml`，支持 Patch/Minor/Major 自动递增或自定义版本
- **Release Notes 与 Changelog**：自动提取最近的 OpenSpec 规约更新与 Git 提交，同步维护 `CHANGELOG.md`
- **Git Tag 与远程推送**：生成带详细说明的附注标签（Annotated Tag），同步推送分支与标签至远程仓库

**使用方法：**
```bash
# 交互式向导（推荐）：逐步确认提交说明、版本号与发布选项
./scripts/release.sh

# 自动递增补丁版本 (0.1.0 -> 0.1.1) 并直接发布
./scripts/release.sh --patch -y

# 自动递增次版本号 (0.1.0 -> 0.2.0)
./scripts/release.sh --minor -y

# 指定版本号与提交说明
./scripts/release.sh 0.2.0 "feat: release v0.2.0"

# 仅本地完成提交与 Tag 打包（不推送到远程仓库）
./scripts/release.sh --no-push
```

### push_codes.sh
代码推送脚本。

**功能：**
- 自动推送代码到远程仓库