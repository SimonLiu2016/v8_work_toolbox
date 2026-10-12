## Context

参考 `proposal.md`。Dola 号池在初次落地后，用户在实际操作中暴露了 4 个具体易用性与逻辑缺陷：Cookie 提取指引、探活网络端点协议对齐、工坊设置项持久化和看板错误信息交互。

## Decisions

### 1. 探活协议修正
- 将探测地址修正为 `https://www.dola.com/alice/user/get_web_anon_id`，请求方法为 POST，并在返回响应头中检查 `x-tt-agw-login: 1`。

### 2. 工坊设置持久化
- 在 `SettingsStore` 中扩展两个键值：
  - `studio_preferred_image_engine` (默认 `system-image`)
  - `studio_preferred_video_engine` (默认 `system-video`)
- `StudioSettingsDialog` 的 `_load()` 从 `SettingsStore` 读取，并在 `_save()` 或切换时调用持久化保存。

### 3. 可用性测试分支补全
- 在 `_test()` 的 switch 中加入：
  ```dart
  'dola-pool-seedance-2.5' => await (await VideoGenAdapterFactory.create(preferredEngineId: 'dola-pool-seedance-2.5')).isAvailable(),
  'dola-pool-seedance-2.0' => await (await VideoGenAdapterFactory.create(preferredEngineId: 'dola-pool-seedance-2.0')).isAvailable(),
  ```

### 4. 分镜看板体验优化
- `_enqueueClip(shot)` 开头检查 `shot.framePath != null && shot.framePath!.isNotEmpty && File(shot.framePath!).existsSync()`，若不存在则提示需先生成首帧；
- 失败任务展示增加点击查看弹窗，弹窗内使用 `SelectableText`，底部放置「复制错误详情」按钮。
