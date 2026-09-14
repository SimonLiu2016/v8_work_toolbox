# Tasks: dek-file-fallback-for-unsigned-app

## 1. KekManager 文件回退

- [x] 1.1 `KekManager` 新增文件 DEK 路径：`.dek`（0600 权限，base64url 编码，含 `v8dek1:` 标记）
- [x] 1.2 读取链：Keychain 读 → 文件读 → 生成（先尝试 Keychain 写，失败写文件）
- [x] 1.3 `DekSource` 枚举（keychain / file / ephemeral / none）暴露给 UI
- [x] 1.4 权限强制：写入后 `chmod 600`；测试验证 0600
- [x] 1.5 自动迁移：Keychain 可写 + 文件存在 → 写回 Keychain 并删除文件

## 2. 测试

- [x] 2.1 `test/kek_manager_test.dart` 扩展：文件回退读写、0600 权限验证、Keychain 恢复后自动迁移、读取损坏文件（16 条全过）
- [x] 2.2 启动集成测试：模拟 Keychain 全拒 → 应用正常初始化、写入读回一致（`test/startup_dek_fallback_test.dart`，3 条）

## 3. UI 与部署

- [x] 3.1 设置面板显示当前 DEK 来源（macOS 钥匙串 / 本地文件 0600 权限 / 未初始化）
- [x] 3.2 重新构建 Release 并替换 /Applications：已完成（17:29 构建，可执行文件 17:29:27，进程启动后托盘初始化成功、启动日志 0 次 FormatException / 0 次崩溃），黑屏消除已验证
      - 未验证项（留给用户真机操作）：密码工具面板内的密钥写入读回、重启后 vault 数据持久。注：未检测到 `~/.dek`/`.vault.bin`，说明用户尚未打开过密码工具，DEK 仍在首次初始化路径上
