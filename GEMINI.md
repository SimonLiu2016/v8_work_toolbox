# V8WorkToolbox 工程级规范与记忆

## 核心执行规则：代码修改完成后必须自动重新构建并替换本机应用

在当前工程 (`V8WorkToolbox`) 中，无论是完成 bug 修复、功能迭代还是规约实施（OpenSpec apply 等），**修改完工程代码后必须执行以下命令重新构建并替换本机应用**：

```bash
./scripts/deploy_local.sh
```

此脚本自动完成：
- `flutter clean` & Release 构建
- 提取并保留第三方运行时二进制（如 mihomo）
- ad-hoc 重新签名以满足 macOS 权限与 Keychain 要求
- 优雅关闭旧实例，更新 `/Applications/V8WorkToolbox.app` 并启动最新实例
- 比对 Dart AOT md5 确保代码已成功生效

## 版本发布与防丢失远程同步规则

在本地验证完成、功能或 Bug 修复交付后，通过以下命令一键将代码、版本、标签与 Release Notes 完备发布至远程 Git 仓库：

```bash
./scripts/release.sh
```

此脚本自动完成：
- 全量暂存并提交工作区所有未保存与未跟踪代码，杜绝因本地分支切换或误操作导致代码覆盖丢失
- 支持特性分支一键安全合并入 `main`
- 智能自适应网络与代理环境（支持直连与本地代理端口回退）
- 语义化版本更新（自动同步 `pubspec.yaml`）
- 提取 OpenSpec 规约更新与 Git Log，自动生成/更新 `CHANGELOG.md` 与 Release Notes
- 创建 Git 附注 Tag（Annotated Tag）并全量推送分支与 Tag 至远程仓库

