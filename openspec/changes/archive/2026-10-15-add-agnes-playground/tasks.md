## 1. 视频请求契约扩展（适配器层）

- [x] 1.1 `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`VideoGenRequest` 增加 `lastFrameImage`、`mode`（枚举 `auto`/`text`/`keyframe`/`reference`）、`sizeTier`、`ratio`、`seed` 字段，默认值均为"不指定"；`allImages` 纳入尾帧
- [x] 1.2 同文件：新增 `AgnesVideoMode` 枚举与按官方规则表推导模式的方法（有首或尾帧→keyframe；有参考图且无首尾帧→reference；皆无→text）；显式 mode 与媒体实况冲突时抛 `StateError`
- [x] 1.3 同文件：`AgnesVideoAdapter.generateVideo` payload 支持 `last_frame`、`images`（reference 模式，data URI）、随请求的 `size` 与 `aspect_ratio`；三种模式的互斥字段严格排除
- [x] 1.4 同文件：`size` 大小写归一（能力矩阵小写 → Agnes 大写）；`seed` 非空时进 payload
- [x] 1.5 同文件：把首帧尺寸守卫提为私有静态方法，首帧与尾帧共用（边长 256–5760、超 720×1280 等比缩放、JPEG 80）
- [x] 1.6 同文件：`NormalizingVideoAdapter` 透传全部新字段，并把 `resolution: request.sizeTier`、`ratio: request.ratio`、`hasLastFrame: request.lastFrameImage != null` 接进 `MediaRequestSpec`

## 2. 适配器层测试

- [x] 2.1 `test/ai_video_studio_adapter_test.dart`：仅首帧 / 仅尾帧 / 首尾帧齐备三种 payload 形态，断言 `mode: "keyframe"` 与对应字段
- [x] 2.2 同文件：仅参考图（显式 reference）→ `mode: "reference"` 且 `images` 数组提交、`first_frame`/`last_frame` 缺席；纯提示词 → `mode: "text"` 且无任何媒体字段
- [x] 2.3 同文件：显式 keyframe + 参考图时拒绝提交并抛出可读原因，且 HTTP 未被调用
- [x] 2.4 同文件：请求 `2k`（小写）时提交大写 `2K`；经 `NormalizingVideoAdapter` 包装时 Flash 型号被吸附为 `720P` 且 `lastChanges` 非空
- [x] 2.5 同文件：**行为兼容断言**——不传 `mode`/`sizeTier`/`ratio`/`seed` 时，提交 payload 与改动前逐字一致（`size: '720P'`、`aspect_ratio: '9:16'`、无 `last_frame`/`images`）；另加一条 auto 推导回归：片段级形状（多参考图无首帧）仍走 keyframe
- [x] 2.6 同文件：尾帧复用尺寸守卫——过小尾帧被拒、超大尾帧被缩放并编码为 JPEG

## 3. 能力声明对齐

- [x] 3.1 `lib/services/media_capability.dart`：`agnesVideo25` 与 `agnesVideo25Flash` 的 `ratios` 补 `21:9`（官方六种白名单）
- [x] 3.2 同文件：注释记录官方实测输出尺寸映射，写明两个型号同比例输出不同（标准版 16:9 = 1280×720，Flash 16:9 = 1280×704）
- [x] 3.3 同文件：`supportsNativeAudio` 注释写明该字段描述输出而非输入参考
- [x] 3.4 `test/media_capability_matrix_test.dart`：断言 Agnes 两型号的比例集合覆盖官方六种、首尾帧声明与适配器可达性一致、`supportsNativeAudio` 为 false 而 reference 模式仍可声明

## 4. 试炼场工具骨架

- [x] 4.1 `lib/services/app_paths.dart`：新增 `videoStudioPlaygroundDir` 与 `videoStudioPlaygroundIndexFile`，并登记进 `allFiles`/目录清单
- [x] 4.2 `lib/tools/tool_definition.dart`：新增 `kToolIdAgnesPlayground` 常量
- [x] 4.3 新增 `lib/tools/agnes_playground/models/playground_models.dart`：通道枚举、媒体角色枚举、请求参数与轮次快照模型（含 `toJson`/`fromJson`）
- [x] 4.4 新增 `lib/tools/agnes_playground/services/playground_store.dart`：`video_studio/playground/` 下的索引与轮次读写，原子替换写；索引记 `sizeBytes` 供后续清理
- [x] 4.5 新增 `lib/tools/agnes_playground/services/playground_service.dart`：三通道调用封装（文本走 `AiService.chat`，图像走图像适配器，视频走 `AgnesVideoAdapter`），落快照前先复制参考图与产物
- [x] 4.6 新增 `lib/tools/agnes_playground/ui/playground_page.dart`：即梦式聊天窗——消息列表、输入栏、通道切换、模型下拉、参数面板（首帧/尾帧/参考图、时长、分辨率档位、画幅比例、种子）、进度与结果展示
- [x] 4.7 同文件：脱敏请求体视图——图片字段渲染为一行摘要（角色 + 尺寸 + 编码体积），不展开 base64
- [x] 4.8 同文件：产物操作——存入资产库（`AssetLibrary.addAsset`，带 `sourceCallId` 指向本次快照）、视频任务的「继续等待」入口
- [x] 4.9 `lib/tools/registry.dart`：注册 `AgnesPlaygroundToolDefinition`（分类 `ai`，`openInNewWindow: true`，独立窗口逻辑照 `AiVideoStudioToolDefinition`）
- [x] 4.10 `lib/main.dart`：新增 `WindowKind.agnesPlayground` 与子窗口分支，必需服务清单取 `_appPaths`/`_settingsStore`/`_proxy`/`_aiConfig`/`_dolaStore`
- [x] 4.11 `lib/tools/ai_video_studio/ui/studio_shell.dart` 或设置对话框：增加「打开试炼场」入口

## 5. 试炼场测试

- [x] 5.1 新增 `test/tools/agnes_playground/playground_store_test.dart`：快照写入/读取往返、媒体副本独立于原文件、失败调用也留痕
- [x] 5.2 新增 `test/tools/agnes_playground/playground_service_test.dart`：三通道 mock HTTP 下的调用与快照落盘；视频任务超时置为云端处理中而非失败
- [x] 5.3 新增 `test/tools/agnes_playground/playground_page_test.dart`：无剧集时可渲染；reference 模式下参考图标注占位符编号；参数面板按型号收敛分辨率档位
- [x] 5.4 `test/password_vault_registry_test.dart` 同款位置补试炼场注册断言：id、分类、`openInNewWindow`、出现在公开工具列表、可被全局搜索命中

## 6. 回归与文档

- [x] 6.1 跑 `flutter test` 全量，确认工坊现有生成链路测试无回归
- [x] 6.2 补一条针对 `storyboard-visual-composition` spec 的回归：撤销"禁传 size"后，中转站网关路径若仍需兼容由重试逻辑兜底（确认现有 429/502/503/400 重试未被本次改动削弱）
- [x] 6.3 `docs/` 下补试炼场使用说明：三通道、参数含义、`<Picture N>` 占位符写法、脱敏视图怎么看
