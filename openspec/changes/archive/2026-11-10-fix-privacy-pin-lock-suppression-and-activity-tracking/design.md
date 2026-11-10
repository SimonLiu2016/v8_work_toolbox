## Context

`PrivacySecurityService` 提供媒体播放抑制器机制（`PlaybackInhibitor`）以及闲置检测机制（`checkIdleTimeout`）。随心短剧接入到系统后，缺少对 `PlaybackInhibitor` 的注册，同时由于短剧界面没有将鼠标移动/点击等行为接入 `recordActivity()`，导致在短剧内持续播放或刚完成交互时仍然会触发闲置超时自动锁屏。

## Goals / Non-Goals

**Goals:**
- 随心短剧播放中（`isPlaying == true`）完全抑制隐私空间自动锁屏。
- 隐私空间主视图全局捕获鼠标与触控事件（hover, down, signal），实时重置闲置计时器。
- 随心短剧的关键操作（如搜索、换题材标签、切选集）主动触发 `recordActivity()`。
- 完善控制器释放流程，销毁时注销抑制器，防止内存泄漏或幽灵抑制。

**Non-Goals:**
- 不改变 6 位 PIN 码加盐哈希与 Keychain 安全存储模型。
- 不修改公网非隐私工具栏的生命周期行为。

## Decisions

### 1. 播放抑制器：在 `CasualShortDramaController` 声明周期内动态注入
- **方案**：在控制器构造函数 `_bindSecurityListener` 中增加 `_playbackInhibitor = () => isPlaying;`，并调用 `_privacyService.registerPlaybackInhibitor(_playbackInhibitor)`；在 `dispose()` 时注销。
- **替代方案考虑**：仅在 UI 层注册。弊端是若界面全屏或重建，抑制器状态容易中断；放在持久控制器单例中能稳定反映真实的播放器状态。

### 2. 用户活跃度追踪：AppShell 隐私层全局包裹 + 短剧业务层防御性埋点
- **方案**：
  1. 在 `AppShell` 的隐私主视区外层包裹透明 `Listener(behavior: HitTestBehavior.translucent, onPointerHover: ..., onPointerDown: ..., onPointerSignal: ...)`，集中刷新 `recordActivity()`。这让隐私空间下所有工具（短剧、密码箱、视频库等）都能天然获得全量指针活跃续期。
  2. 在 `CasualShortDramaController` 的核心业务逻辑（`searchDramas`、`selectTag`、`playDrama`、`changeEpisode`）主动调用 `_privacyService.recordActivity()`，即便用户使用外接键盘或快捷指令，也能有效保活。

## Risks / Trade-offs

- **[Risk]** 控制器单例长期常驻导致抑制器常开？
  - **Mitigation**: 抑制器实现为闭包 `() => isPlaying`，只有当底层播放器真正处于 `isPlaying == true` 时才返回 true；剧集播完或暂停时自动返回 false，闲置计时立即恢复正常。
- **[Risk]** 全局指针 `onPointerHover` 过于频繁调用 `DateTime.now()`？
  - **Mitigation**: `recordActivity()` 内部仅执行一次极简的赋值 `_lastActiveTime = DateTime.now()`，开销可忽略不计；亦可在 service 内做节流，但目前纳秒级赋值对 60fps/120fps 渲染无任何压力。
