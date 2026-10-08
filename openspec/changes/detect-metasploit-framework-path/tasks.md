## 1. 路径与子进程非阻塞执行改造

- [x] 1.1 在 `SecurityProcessRunner` 中定义 `kSecurityAppBinDirs`，包含 `/opt/metasploit-framework/bin` 与 `/opt/metasploit-framework/embedded/bin`
- [x] 1.2 将 `kSecurityAppBinDirs` 整合进 `SecurityProcessRunner.augmentedPath` 与 `resolveExecutable` 目录解析中
- [x] 1.3 在 `SecurityProcessRunner.runCaptured` 中进程启动后立即安全关闭 `stdin`，防止交互式会话挂起

## 2. 自动化测试与验证

- [x] 2.1 在 `test/security_toolbox_test.dart` 中增加对 `/opt/metasploit-framework/bin` 的路径解析测试
- [x] 2.2 运行 Flutter 单元测试并确保通过
- [x] 2.3 重新编译并打包部署本地应用至 `/Applications/V8WorkToolbox.app`
