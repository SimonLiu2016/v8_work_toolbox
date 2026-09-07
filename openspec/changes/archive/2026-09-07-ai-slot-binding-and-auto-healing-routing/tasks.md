## 1. Data Model — SlotCandidate 与配置存储升级

- [x] 1.1 在 `lib/services/ai_config_store.dart` 中新建 `SlotCandidate` 值类（`providerId`, `model`, `priority`），包含 `toJson()` / `fromJson()` / `copyWith()`
- [x] 1.2 将 `AiConfigStore._slotBindings` 类型从 `Map<String, Map<String, String>>` 改为 `Map<String, List<SlotCandidate>>`，更新 `slotBindings` getter 返回类型
- [x] 1.3 更新 `_initDefaults()` 为每个槽位初始化空候选列表 `[]`
- [x] 1.4 更新 `_load()` 实现向后兼容：检测 `defaultSlots` 值为 Map（旧格式）或 List（新格式），旧格式自动迁移为单元素 `[SlotCandidate]` 并立即 `_save()`
- [x] 1.5 更新 `_save()` 序列化 `defaultSlots` 为新格式（候选列表）
- [x] 1.6 新增 `addSlotCandidate(slotName, providerId, model)` 方法，追加到最低优先级位置并持久化
- [x] 1.7 新增 `removeSlotCandidate(slotName, index)` 方法，移除指定位置的候选并持久化
- [x] 1.8 新增 `reorderSlotCandidates(slotName, oldIndex, newIndex)` 方法，更新优先级顺序并持久化
- [x] 1.9 更新 `deleteProvider()` 清理逻辑：遍历所有槽位的候选列表，移除引用了被删除供应商的候选项
- [x] 1.10 更新 `setSlotBinding()` 方法签名以兼容新数据结构（或标记 @deprecated 并引导使用新 API）

## 2. 健康状态缓存与供应商健康追踪

- [x] 2.1 在 `lib/services/ai_service.dart` 中新建 `ProviderHealthState` 类（`isHealthy`, `lastCheckedAt`, `lastError`, `failureCount`）
- [x] 2.2 在 `AiService` 中添加 `Map<String, ProviderHealthState> _healthCache` 实例字段
- [x] 2.3 添加 `_isProviderHealthy(providerId)` 方法，检查健康缓存中的状态和冷却窗口（默认 60 秒）
- [x] 2.4 添加 `_markProviderHealthy(providerId)` 方法，更新缓存为健康状态
- [x] 2.5 添加 `_markProviderUnhealthy(providerId, error)` 方法，记录失败时间戳和错误信息
- [x] 2.6 添加 `cooldownDuration` 可配置常量（默认 `Duration(seconds: 60)`），暴露 `@visibleForTesting` setter
- [x] 2.7 添加 `getProviderHealth(providerId)` 公开 getter 供 UI 层读取健康状态

## 3. 路由引擎与自动降级

- [x] 3.1 新建 `RouteAttempt` 类（`providerId`, `model`, `outcome`, `durationMs`, `error?`）
- [x] 3.2 新建 `ChatResult` 类（`text`, `usedProviderId`, `usedModel`, `routingTrace: List<RouteAttempt>`），提供 `ChatResult.text` 便捷 getter
- [x] 3.3 新建 `SlotUnavailableException` 类（`slotName`, `candidateCount`, `candidateErrors: List<String>`），继承 `Exception` 并提供结构化 `toString()`
- [x] 3.4 重构 `chat()` 方法：将返回类型从 `Future<String>` 改为 `Future<ChatResult>`
- [x] 3.5 实现 `chat()` 中的多候选路由循环：按优先级遍历槽位候选列表，跳过冷却中的不健康供应商，尝试请求，失败则标记不健康并继续下一个
- [x] 3.6 在路由循环中记录每次尝试到 `routingTrace`（包括跳过的和实际请求的）
- [x] 3.7 当所有候选耗尽或槽位无候选时，抛出 `SlotUnavailableException`
- [x] 3.8 保留 `explicitProviderId` / `explicitModel` 直通路径：当调用者显式指定时跳过路由逻辑，直接调用指定供应商

## 4. AI 配置页 UI — 多候选管理与健康展示

- [x] 4.1 重构 `_buildSlotsTab()` 为多候选列表视图，每个槽位显示 `ReorderableListView` 形式的候选卡片列表
- [x] 4.2 每个候选卡片展示：供应商名称、模型名、健康状态圆点（绿/黄/红）、删除按钮
- [x] 4.3 实现拖拽排序交互：`onReorder` 回调调用 `AiConfigStore.reorderSlotCandidates()`
- [x] 4.4 添加"添加候选"按钮与弹窗：选择供应商 → 选择模型 → 调用 `addSlotCandidate()`
- [x] 4.5 在每个槽位标题旁添加聚合健康指示器（绿色=全部健康 / 黄色=已降级 / 红色=全部不可用）
- [x] 4.6 黄色/红色状态下显示当前活跃供应商名称和最近降级事件的时间文本
- [x] 4.7 健康状态轮询：使用 `Timer.periodic`（每 10 秒）刷新健康指示器 UI，在 `dispose()` 中取消定时器

## 5. 调用者迁移

- [x] 5.1 搜索所有 `AiService.instance.chat(` 调用点，将返回值从 `String` 改为 `ChatResult`，使用 `.text` 获取文本内容
- [x] 5.2 在 Smart Disk Slimmer 的 AI 批量诊断中，捕获 `SlotUnavailableException` 并展示结构化错误引导（替换当前泛型 catch）
- [x] 5.3 确保 `explicitProviderId` 直通路径的现有调用无需改动（验证兼容性）

## 6. 验证与测试

- [x] 6.1 编写 `SlotCandidate` 序列化/反序列化单元测试
- [x] 6.2 编写 `AiConfigStore` 旧格式自动迁移单元测试：加载旧 `ai_config.json` → 验证候选列表 → 验证重新保存后格式正确
- [x] 6.3 编写 `ProviderHealthState` 冷却窗口逻辑单元测试
- [x] 6.4 编写 `chat()` 路由降级集成测试（mock HTTP client）：首选失败→备选成功→验证 `ChatResult` 路由跟踪
- [x] 6.5 编写 `SlotUnavailableException` 测试：零候选和全部失败两种场景
- [x] 6.6 手动验证：配置 2+ 供应商，断开首选供应商网络 → 验证自动切换 → 恢复首选 → 验证回切
- [x] 6.7 运行 `flutter analyze --no-fatal-infos` 确认零错误零警告
