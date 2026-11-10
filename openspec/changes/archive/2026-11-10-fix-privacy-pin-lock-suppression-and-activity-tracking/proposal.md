## Why

在隐私空间使用「随心短剧」工具时，用户在进行正常交互（如搜索短剧、切换题材、点击剧集）后不久，或正在观看剧集播放时，6 位数字 PIN 安全锁仍会被强制触发锁屏。这是因为随心短剧控制器未向 `PrivacySecurityService` 注册媒体播放状态抑制器 (`PlaybackInhibitor`)，且短剧交互及隐私视图未统一上报用户活跃时间 (`recordActivity()`)，导致闲置超时判定误判。

## What Changes

1. **短剧播放状态自动抑制锁屏**：在 `CasualShortDramaController` 中向 `PrivacySecurityService` 注册 `PlaybackInhibitor`（`() => isPlaying`），只要短剧正在播放，自动抑制 PIN 锁屏并刷新活跃时间；控制器销毁时安全注销。
2. **全局隐私空间交互活跃检测**：在 `AppShell` 的隐私空间主视图层挂载通用半透明 `Listener`，对指针移动 (`onPointerHover`)、点击 (`onPointerDown`)、滚轮 (`onPointerSignal`) 等所有交互统一调用 `recordActivity()`，杜绝在操作过程中被闲置超时误判。
3. **关键业务动作主动上报**：在 `CasualShortDramaController` 发生搜索、题材切换、换集、线路切换等重要操作时显式刷新活跃时间。

## Capabilities

### Modified Capabilities
- `privacy-space`: 补充规范随心短剧播放中的防自动锁屏与隐私视图交互全量活跃刷新机制。

## Impact

- `lib/tools/casual_short_drama/services/casual_short_drama_controller.dart`: 注入 `PlaybackInhibitor` 并在销毁时注销；重要操作触发 `recordActivity()`。
- `lib/shell/app_shell.dart`: 在 `ActivityViewType.privacy` 视图外层包裹活跃监听器，统一保障隐私空间内所有工具的活跃检测。
- `lib/tools/casual_short_drama/ui/casual_short_drama_page.dart`: 在页面层补充指针与交互监听。
- `test/casual_short_drama_api_test.dart` / 单元测试：新增短剧播放抑制与活跃刷新测试用例。
