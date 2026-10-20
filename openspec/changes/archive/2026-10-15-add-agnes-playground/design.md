## Context

现状与约束（动机见 proposal.md - Why）：

- Agnes 三个通道的底层都已存在：文本走 `AiService.chat()`（无流式），图像走 `SystemAiImageAdapter` 的 Agnes 分支，视频走 `AgnesVideoAdapter` + `VideoTaskLedger` + `VideoTaskRecovery`。
- `AgnesVideoAdapter` 把 `aspect_ratio` 写死 `9:16`、`_sizeTier` 两分支都返回 `'720P'`、没有 `last_frame`、只有 `isKeyframe` 布尔表达模式（表达不了官方第三种模式 `reference`）。
- `NormalizingVideoAdapter` 是既有的规整层，但它今天向 `MediaRequestSpec` 传的 `resolution`/`ratio` 是空串、`hasLastFrame` 恒 false——吸附能力是通的，只是视频路径没接上。
- 能力矩阵用 `AiProtocolType.agnes` 标识协议，`MediaCapabilityPresets` 已有 `agnesVideo25` / `agnesVideo25Flash` / `agnesImage` 三条声明。
- 子窗口通过 `main.dart` 的 `WindowKind` + 必需服务清单启动；工坊已有 `WindowKind.aiVideoStudio` 可照抄。
- 资产库（`AssetLibrary`）与调用台账（`VideoTaskLedger`）属于在飞变更 `add-studio-asset-library-with-remote-call-ledger`，本次直接复用，不重建。

约束：本地文件只能以 data URI 提交（服务端无法访问本机路径）；`first_frame` 现已验证 data URI 可用，`images[]` 走同一编码路径。

## Goals / Non-Goals

**Goals:**

- 试炼场作为独立工具存在，无剧集也能用全部三通道。
- 每一轮调用自包含留痕，含参考图副本与脱敏请求体视图。
- 视频请求契约补尾帧、可调 `size`/`ratio`、三态模式与官方互斥校验，且改动对工坊主路径**行为兼容**（不传新字段时提交体与今天逐字一致）。
- 能力声明与官方文档对齐，`supportsLastFrame` 从"声明了但不可达"变为真实可达。

**Non-Goals:**

- 不把工坊的片段级生成切到 reference 模式（需要单独 change + 实测对比）。
- 不给 `StudioShot` 加尾帧字段、不改分镜看板 UI。
- 不做 A/B 对比 UI、不做调用历史的多轮会话组织、不做音频参考输入。
- 不实现 `{{ref N}}` → `<Picture N>` 的自动转换。
- 不做流式输出（`AiService` 无流式，本次不引入）。

## Decisions

### 决策 1：试炼场是独立工具，不是工坊的第八个工序页

工坊侧导航的注释明确它是「工序」而非「功能」，按制作顺序前进（创意孵化→IP 主库→分镜看板→声音设计→合成交付）。试炼场不是工序，且不该有「未选剧集不可用」这道门。

备选：塞进 `StudioStage`。否——它要么被 `_needsSeries` 挡住，要么成为第一个不受该约束的工序页，两种都破坏那条不变式。

实现为 `ToolCategory.ai` 下的独立工具，`openInNewWindow: true`（与工坊、笔记本、密码工具一致——长轮询任务不该被主窗口切走打断）。工坊设置对话框加一个「打开试炼场」入口，服务层零重复。

### 决策 2：试炼场快照是自包含目录 + 单 JSON 索引，与台账分开存

```
video_studio/playground/
├── index.json          ← 会话与轮次索引（轻量，可整文件原子写）
├── turns/<turnId>/
│   ├── request.json    ← 提示词、参数（吸附后）、媒体角色标注、错误、耗时
│   ├── request_view.md ← 脱敏请求体视图（可随时从 request.json 重新生成）
│   ├── media/          ← 参考图副本（首帧/尾帧/参考，原样字节）
│   └── output/         ← 产物（图片或视频）
```

**为什么不并进 `VideoTaskLedger`**：台账是账（记生命周期事件、按 7 天窗口清理、与分镜看板的「云端任务」面板共用），试炼场快照是分析材料（要长期保留、要带媒体副本、要能回看"我当时喂了什么"）。两者合并会让清理策略与字段需求互相绑架。

**双写**：视频调用仍照常 `VideoTaskLedger.instance.record(...)`（那是账），试炼场另写自己的快照。图像调用同理——`recordImageCall` 已在做记账，快照层不重复其职责，只补它没记的参考图与参数。

**媒体复制不引用原路径**：与资产库「复制而非移动」同一条理由——原图会被删、被移、被覆盖。

备选：SQLite。否——量级是「几十到几百轮」，单 JSON + 原子写足够，且 `AssetLibrary` 与 `VideoTaskLedger` 都已确立这个模式，引入第三种存储风格没有收益。

### 决策 3：`VideoGenRequest` 增字段而非新类型，模式显式化为枚举

```dart
// 新增
final File? lastFrameImage;
final AgnesVideoMode mode;      // auto | text | keyframe | reference
final String sizeTier;          // '' = 不指定（沿用适配器默认）
final String ratio;             // '' = 不指定
final int? seed;
```

- `inputImage` 保留原名（与 `ImageGenRequest.referenceImagePath` 兼容 getter 同一个理由——改名会让四个适配器与既有测试在一次改动里全炸）。
- `mode` 用 `auto` 作默认值，按官方规则表推导；显式值用于试炼场手动指定与后续 conflict 校验。
- `sizeTier` / `ratio` 空串表示"不指定"：工坊现有调用点不传这两个字段时，提交体与今天逐字一致（`size: '720P'`、`aspect_ratio: '9:16'`），**保证行为兼容**。

`NormalizingVideoAdapter` 改为透传全部新字段，并把 `resolution: request.sizeTier`、`ratio: request.ratio`、`hasLastFrame: request.lastFrameImage != null` 接进 `MediaRequestSpec`——吸附机器本来就是通的。

`VideoGenRequest.allImages` 纳入尾帧，让参考图数量上限的校验覆盖到它。

### 决策 4：AgnesVideoAdapter 按官方模式规则表选模式，互斥在提交前校验

```
显式 mode = keyframe   → keyframe（需首帧或尾帧；禁参考图）
显式 mode = reference  → reference（需参考图；禁首帧与尾帧）
显式 mode = text       → text（无任何媒体字段）
mode = auto 且显式给了首帧或尾帧 → keyframe
mode = auto 且只有参考图          → keyframe（第一张参考图提升为首帧）
mode = auto 且什么都没有          → text
```

显式 `mode` 与媒体实况冲突时抛 `StateError` 并说明原因，不提交。

**`auto` 下"只有参考图"仍走 keyframe，不走 reference**——这是**刻意的选择**：工坊的 `SegmentVideoGenTask` 传的正是 `inputImage: null` + 多参考图，它今天走 keyframe（第一张参考图当首帧）。若 auto 改判 reference，主路径的提交体会从 `first_frame` 变成 `images[]`，那是本次明确列在 Non-Goals 里的行为变更。

要让某个调用走 reference，必须**显式传** `mode: AgnesVideoMode.reference`。试炼场因此可以三种模式都手动选；工坊那条链路等单独 change 做实测对比后再切。

**`size` 大小写归一**：能力矩阵用小写（`'720p'`/`'1k'`），Agnes 要大写（`'720P'`/`'1K'`）。在适配器内做一次归一，而不是改矩阵的大小写——矩阵里 SenseAudio/Dola 都用小写，为一个供应商改全局约定会波及无关分支。

**尾帧复用首帧的尺寸守卫**：边长 256–5760、超过 720×1280 等比缩放、编码 JPEG 80。守卫逻辑提为私有静态方法，首帧尾帧共用。

**工坊调用点不传 `mode`**：`SegmentVideoGenTask` 仍传 `inputImage: null` + 多参考图，`auto` 推导结果仍是 `keyframe`（第一张参考图提升为首帧）——与今天行为一致。reference 模式的切换留作单独 change，由调用方显式传 `mode` 触发。

### 决策 5：三通道各自薄封装，试炼场不碰适配器内部

试炼场服务层只做三件事：收集参数 → 调既有入口 → 写快照。

- 文本：`AiService.chat(slot: 'text', explicitProviderId:, explicitModel:, messages:)`。
- 图像：`ImageGenAdapterFactory.create(preferredEngineId:)` 或直接构造 `SystemAiImageAdapter`，传 `ImageGenRequest`（含 `referenceImages`、`width`/`height`）。
- 视频：构造 `AgnesVideoAdapter`（按所选供应商填 `baseUrl`/`apiKey`/`providerId`/`model`），传 `VideoGenRequest`，用 `onProgress` 推进度。

试炼场 UI 侧自己维护通道选择、模型下拉（取自 `AiConfigStore.providers` 的 `imageModels`/`videoModels`/`textModels` 与槽位绑定），不引入新的供应商发现逻辑。

HTTP 走 `AppHttpClient.create(toolId: kToolIdAgnesPlayground)`，让试炼场遵循全局代理设置。

### 决策 6：reference 模式的占位符提示是 UI 职责，不做自动转换

提示词组装器输出 `{{ref N}}`（工坊内部契约，需调用方替换），Agnes reference 模式原生识别 `<Picture N>`（供应商契约）。两者语义不同、受众不同，自动转换会让两边都有第二套真相。

试炼场在每张参考图缩略图下直接显示「以 `<Picture N>` 指代」，用户照着写。工坊那条链路的替换逻辑本次不碰。

### 决策 7：能力声明补齐 Flash 输出尺寸映射

官方实测表显示两个型号在同比例下输出不同：`agnes-video-2.5` 的 16:9 = 1280×720，`agnes-video-2.5-flash` 的 16:9 = 1280×704。这个差异写进 `media_capability.dart` 的注释（声明字段本身没有"输出像素"这一维，加一个字段会波及全部型号的序列化与测试）。

`supportsNativeAudio` 的语义纠正在 spec 中写明（描述输出，不是输入），代码注释同步。

## Risks / Trade-offs

- **`images[]` 接受 data URI 未经实测** → `first_frame` 已验证可用，`images[]` 走同一编码路径，风险可控。首次真实调用若被拒，错误信息会直接指出问题；不为此预先搭上传通道。
- **`size`/`ratio` 参数化可能让工坊主路径行为变化** → 空串约定保证不传时提交体不变；适配器层测试固定断言"不传新字段时 payload 与改动前逐字一致"。
- **reference 模式的 `mode` 切换会改变片段级生成行为** → 本次不切，工坊调用点不传显式 `mode`，推导结果与现状一致。
- **快照目录随使用无限增长** → 产物是图片与视频，体积不小。v1 不加清理策略，但索引里记 `sizeBytes`，为后续按容量清理留数据；若用户反馈占用再补。
- **文本通道无流式，长回答期间界面无反馈** → 按钮进入 loading 态并提示"等待返回"，不做假进度条。
- **在飞变更 `add-studio-asset-library-with-remote-call-ledger` 未归档** → 试炼场依赖 `AssetLibrary` 与 `VideoTaskLedger` 的现有 API（`addAsset` / `record` / `update` / `resumePolling`）。这些 API 已稳定存在，依赖的是代码而非 spec。

## Migration Plan

无数据迁移：新增工具与新增目录都不影响既有配置键与产物。

部署：`flutter build macos --release` + `scripts/deploy_local.sh`。

回滚：移除 `ToolRegistry` 条目与 `WindowKind` 分支即可，快照目录可留可删（无其他代码读它）。

## Open Questions

- 试炼场的视频任务是否要在 UI 上单独列一张「试炼场任务」清单，还是直接复用分镜看板的「云端任务」面板？——两者都可行且不影响 spec；v1 倾向只在试炼场内显示，面板复用留到有真实反馈后。
- `seed` 是否需要支持"随机生成并记录"按钮（用户不想自己想一个）？纯交互细节，不影响 spec。
