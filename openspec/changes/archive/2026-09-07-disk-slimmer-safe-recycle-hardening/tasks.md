## 1. 废纸篓回收服务加固 (SystemService)

- [x] 1.1 在 `lib/services/system_service.dart` 中定义 `RecycleResult` 数据结构
- [x] 1.2 修复 `SystemService.recyclePaths`：移除 AppleScript 静默吞错，加入 `/usr/bin/trash` 与超时处理
- [x] 1.3 在 `SystemService.recyclePaths` 结尾实施绝对物理后置核验（`Directory/File.existsSync()`），准确返回成功与失败路径列表

## 2. 界面状态与权限提示治理 (SmartDiskSlimmerPage)

- [x] 2.1 改造 `SmartDiskSlimmerPage._performCleanSelected`：接收 `RecycleResult`，仅从列表中移除物理已确认删除的条目
- [x] 2.2 针对部分失败与全部失败场景，保留失败条目在列表中，弹出明确的权限提示弹窗，并提供前往「系统设置 -> 隐私与安全性 -> 完全磁盘访问权限」的操作按钮

## 3. 自动化测试与验证

- [x] 3.1 编写 `test/safe_recycle_hardening_test.dart` 覆盖物理后置核验、部分失败、成功移除与失败保留逻辑
- [x] 3.2 运行全量测试并执行 `flutter analyze --no-fatal-infos` 确认 0 错误 0 警告

## 4. 沙盒容器内核保护感知与深度 Payload 清理 (方案 2)

- [x] 4.1 在 `SystemService` 中实现 `cleanContainerPayload`，严格执行 `followLinks: false`，绝不触碰和删除外部软链接目标（Desktop, Documents, etc.）
- [x] 4.2 当沙盒容器根目录受 macOS `containermanagerd` 内核保护无法直接 unlink 时，自动降级安全清空 `Data/Library/` (Caches, Application Support 非链接数据, WebKit 等)，真实释放磁盘空间
- [x] 4.3 在 `SmartDiskSlimmerPage` 界面中准确反馈沙盒容器深度清空状态与释放空间量
- [x] 4.4 编写针对软链接绝对安全与沙盒降级清理的自动化单元测试并全量通过
