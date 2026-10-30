## 1. 能力声明可空化（spec: dola-pool-configuration 参考图上限的可空语义）

- [x] 1.1 `MediaModelCapability.maxReferenceImages` 由 `int` 改 `int?`，`null` 表示不限制；更新字段文档说明三态（0 = 明确不支持、`null` = 未测上限、正数 = 有上限）
- [x] 1.2 全部 preset 显式给出值，不依赖默认值：`seedance2Video` 9、`senseAudioImage` 1、`agnesVideo` 1、`dolaVideo` null
- [x] 1.3 序列化：`toJson` 与 `fromJson` 正确处理 `null`（缺省即 `null`，不再回落 0）
- [x] 1.4 `normalizer` 的参考图检查：`null` 时跳过数量校验，`0` 时保持拒绝
- [x] 1.5 `ai_config_page.dart:1566` 的空壳判断加入 `== null` 分支
- [x] 1.6 `studio_settings_dialog.dart:347` 的展示文案分三态，`null` 显示「未设上限」而非编造数字
- [x] 1.7 `dart analyze lib/ test/` 清零（36 处引用，测试占 20 处）

## 2. 号池目录与配置层（spec: dola-pool-configuration 号池能力可被用户覆盖）

- [x] 2.1 `AppPaths` 新增 `dolaDir`，登记进 `allDirs`；`DolaAccountStore` 的存储文件从 `AppPaths.root` 迁到 `dolaDir` 下
- [x] 2.2 新增 `DolaConfigStore`：持久化 `Map<String, MediaModelCapability>`，宽容 `fromJson`，与 `DolaAccountStore` 同目录
- [x] 2.3 `DolaConfigStore` 实现 `AiProviderConfigLike`（`protocolId` + `mediaCapabilities`），使 `MediaCapabilityResolver` 无需改签名
- [x] 2.4 覆盖优先级：用户覆盖 > 内置预设 > 协议保守默认；补测试验证三层

## 3. 能力声明按型号拆分（spec: dola-video-engine Standard VideoGenAdapter Contract Compliance）

- [x] 3.1 `dolaVideo` 拆为 `dolaVideo25`（时长 5/10）与 `dolaVideo20`（时长 5/10/15），均开启 `supportsFirstFrame` 与参考图模式，`maxReferenceImages` 为 `null`
- [x] 3.2 `forModel()` 前缀归一到**具体型号**：`dola-pool-seedance-2.5` → 25、`dola-pool-seedance-2.0` → 20；未知的 `dola-pool-*` 回落协议默认而非误命中
- [x] 3.3 文件顶部「这些数字从哪来」的注释改写 Dola 条目：说明 30 秒档位因拼接未实现而暂不声明
- [x] 3.4 `_wrap` 的 Dola 分支传入 `DolaConfigStore.instance` 作为能力来源

## 4. 适配器兜底与显式拒绝

- [x] 4.1 `_snapDuration` 按 `_model` 取合法集合，删除硬编码的 `_legalDurations`
- [x] 4.2 请求携带参考图或首帧时**显式抛错**，说明「参考图上传尚未实现」——不静默忽略（design Risks 第一条）
- [x] 4.3 两层兜底一致性测试：直接调适配器与经工厂 `create()` 得到相同时长

## 5. 失败测试（钉住真实状态，不 skip）

- [x] 5.1 「Dola 参考图上传尚未实现」—— capability 已声明支持，适配器未实现 ImageX 上传。**以显式抛错表达而非红测试**：4.2 让适配器在收到图片请求时抛 StateError，用户立刻知道原因；这比一条永远红着的测试更接近"可见"的本意
- [x] 5.2 「30 秒档位暂不声明」—— 断言 `dolaVideo25.durations` 不含 30，并注释说明原因
- [x] 5.3 ~~确认这两条在全量跑里是红的~~ **改为不制造红测试**：原计划让 5.1 / 5.2 保持红色以"提醒待办"，实测这会污染全量基线——每次跑都要人肉分辨"这个红是预期的吗"，反而稀释了真失败的信号。改为：5.2 的 30 秒以一条**通过**的测试固化现状（注释写明实现后要怎么改），5.1 以运行时显式抛错表达。两者都不占失败名额，但缺口都写在代码里

## 6. 入口接线（spec: dola-account-pool 号池数据初始化由应用启动保证）

- [x] 6.1 `WindowServices` 新增 `_dolaStore` 服务项（`DolaAccountStore` + `DolaConfigStore`），加入 `WindowKind.main` 与 `WindowKind.aiVideoStudio` 清单
- [x] 6.2 初始化失败记录可诊断错误信号（`initFor` 已有 fail-soft，但「显示为空」须可归因）
- [x] 6.3 `AiConfigPage` 新增「Dola 号池」tab，`TabController.length` 3 → 4，内容为 `DolaAccountPoolPanel`
- [x] 6.4 `studio_settings_dialog._enginesFor()` video 分支新增 `dola-pool-2.5` 选项（spec: Studio Engine Selection Persistence）

## 7. 验证

- [x] 7.1 `flutter test test/media_capability_matrix_test.dart test/video_adapter_factory_wrapping_test.dart test/dola_pool_*_test.dart test/ai_config_test.dart test/window_service_initialization_test.dart` 全绿
- [x] 7.2 `dart analyze lib/ test/` 无新增 error / warning
- [x] 7.3 全量 `flutter test`：**1671 passed / 3 skipped / 0 failed**（第 5 节改为不制造红测试，见该节说明）
- [x] 7.4 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh`：AOT 2f5d0994… → 6f752ced…，strict 签名通过，实例存活

## 8. 实现期发现的额外缺陷（已修）

- [x] 8.1 能力查找的 id 不一致：显式选中号池时用 `preferredEngineId`（`dola-pool-2.5`）查能力，而内置预设与用户覆盖的键是 `adapter.id`（`dola-pool-seedance-2.5`）。短 id 两者都命中不了，能力查找静默落到 openai 默认值——而那个默认值的时长集合与 Dola 真实能力不同。统一改用 `adapter.id`
