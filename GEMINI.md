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
