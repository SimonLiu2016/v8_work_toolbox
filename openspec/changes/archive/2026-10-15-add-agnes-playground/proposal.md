## Why

短视频工坊把 Agnes 的文本、图像、视频调用全部埋进了制作流程：用户点一次「生成关键帧」或「生成片段」，提示词由 `PromptAssembler` 拼装、参考图由任务按角色/场景隐式挑选、尺寸与画幅由适配器写死。链路有四五层，用户看到的只有一个按钮和一个结果。

后果是**无法归因**：画面不对时，用户分不清是提示词写得不好、参考图选得不对、还是尺寸档位被悄悄降了。更糟的是现有留痕（`VideoTaskLedger`）只记 `model / prompt / outputPath`，没有记「喂了什么」——参考图、尺寸档位、画幅比例、生成模式、随机种子全都没落盘，事后连复盘材料都没有。

同时，适配器层有三处写死使模型能力不可达：`aspect_ratio` 恒为 `9:16`、`_sizeTier` 两个分支都返回 `'720P'`、尾帧字段完全不存在（尽管能力矩阵与工坊设置一直声明"支持首帧与尾帧"）。`storyboard-visual-composition` 的 payload 契约还停留在中转站时代，明文写着 SHALL NOT 传 `size: "720P"`——那条约束对直连 Agnes 已不成立，spec 与代码互相矛盾。

## What Changes

### 1. 新增「Agnes 试炼场」独立工具

一个不挂在任何剧集下的顶层工具（`ToolCategory.ai`，独立窗口），以即梦式聊天窗为载体，提供三个通道直连 Agnes：

- **文本通道**：复用 `AiService.chat()`，可显式指定供应商与型号。`AiService` 无流式，接受整段返回。
- **图像通道**：复用 `SystemAiImageAdapter` 的 Agnes 分支（`size` + `ratio` + `extra_body.image[]` data URI），提示词、参考图、尺寸档位与画幅全部可手填。
- **视频通道**：复用 `AgnesVideoAdapter`，提示词、首帧、尾帧、参考图、时长、分辨率档位、画幅比例、随机种子全部可手填；三种生成模式（`text` / `keyframe` / `reference`）可手动选择。

**核心是请求快照，不是气泡。** 每一轮自包含落盘：提交的提示词逐字、参考图副本及其角色标注（首帧/尾帧/参考）、吸附后的实际参数、产物、耗时、错误、云端任务标识。快照提供**脱敏请求体视图**——把 data URI 替换为 `<first_frame: 720×1280 JPEG 87KB>` 这类一行标记，让用户直接看到"这次到底发了什么"。

随机种子（`seed`）进 v1 必做项：没有它，两次调用的差异里混着随机性，用户根本无法判断提示词改动带来的影响。

试炼场的视频调用同样计入 `VideoTaskLedger` 并可「继续等待」——复用现有台账与恢复路径，不复制第二份。产物可一键存入资产库（复制，与既有约定一致）。

### 2. 视频请求契约补尾帧、分辨率与画幅

`VideoGenRequest` 增加 `lastFrameImage`，并把生成模式从 `isKeyframe` 布尔显式化为三态（`text` / `keyframe` / `reference`）——布尔表达不了 reference，而 reference 才是片段级本该走的路。

`AgnesVideoAdapter` 按官方模式规则表选模式并做互斥校验：有首或尾帧走 `keyframe`（禁 `images`/`audios`/`videos`）；有参考图且无首尾帧走 `reference`（禁 `first_frame`/`last_frame`）；两者皆无走 `text`。`size` 与 `aspect_ratio` 从写死值改为随请求，经 `MediaRequestNormalizer` 吸附后提交。

尾帧与首帧共用同一套尺寸守卫（边长 256–5760、超限转 JPEG 80）。

**工坊调用点本次不切 reference**：管道铺到能发，但 `SegmentVideoGenTask` 仍走现状（参考图第一张隐式提升为首帧）。切换会改变既有生成行为，需要单独 change 加实测对比。

### 3. 能力声明与官方文档对齐

- `agnes-video-2.5`：`size` 四档与 `ratios` 六种改为实际可达（适配器参数化后才成立）。
- `agnes-video-2.5-flash`：`size` 固定 `720P`；补齐官方实测输出尺寸映射（16:9 = 1280×704，与标准版的 1280×720 不同）。
- `supportsNativeAudio` 的语义在 spec 中写明：描述**输出**是否带原生音轨，不是输入侧是否接受音频参考。

### 4. 校准 `storyboard-visual-composition` 的 payload 契约

原要求「SHALL NOT include `'size': '720P'`」源于中转站网关限制，对直连 Agnes 已失效且与代码矛盾。改为：`size` SHALL 从型号支持的档位中取值，`aspect_ratio` SHALL 从白名单取值，非法值 SHALL NOT 提交。

## Capabilities

### New Capabilities

- `agnes-playground`: Agnes 三通道试炼场——可手填提示词、参考图、首尾帧与全部生成参数的直连调用工具；每轮自包含请求快照与脱敏请求体视图，使生成效果与输入的对应关系可归因；视频调用计入云端任务台账并可跨重启继续等待。

### Modified Capabilities

- `storyboard-visual-composition`: Agnes 视频 payload 契约增加 `last_frame`、`size` 档位与 `aspect_ratio` 白名单，生成模式显式化为三态并强制执行官方互斥规则；撤销中转站时代「禁传 size」的过期约束。
- `media-model-capability-matrix`: Agnes 视频两个型号的能力声明改为实际可达——`supportsLastFrame` 从"声明了但无代码路径"变为适配器可提交；`size`/`ratios` 与官方档位对齐；补齐 Flash 的输出尺寸映射；明确 `supportsNativeAudio` 描述输出而非输入。

## Impact

**代码**

- 新增 `lib/tools/agnes_playground/`：工具定义、聊天窗 UI、请求快照存储、三通道调用服务。
- `lib/tools/tool_definition.dart`：新增 `kToolIdAgnesPlayground` 常量。
- `lib/tools/registry.dart`：注册试炼场工具。
- `lib/main.dart`：新增 `WindowKind.agnesPlayground` 与其必需服务清单（复用 `_appPaths` / `_settingsStore` / `_proxy` / `_aiConfig`）。
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`VideoGenRequest` 增字段、`AgnesVideoAdapter` 增尾帧与 reference 模式、`NormalizingVideoAdapter` 透传新字段。
- `lib/services/media_capability.dart`：Agnes 视频能力声明校准。
- `lib/services/app_paths.dart`：试炼场快照目录。
- `lib/tools/ai_video_studio/ui/studio_shell.dart` 或设置对话框：增加「打开试炼场」入口。

**依赖的在飞变更**

- `add-studio-asset-library-with-remote-call-ledger`（34/36）：试炼场复用其资产库与台账。`async-video-task-ledger` 能力尚未进主 spec，故本次不声明对其的 delta，试炼场的台账要求写在 `agnes-playground` 自己的 spec 中。

**配置与数据**

- 新增试炼场快照目录与索引文件；不影响既有配置键，无需迁移。

**测试**

- 适配器层：尾帧 payload、三态模式选择与互斥拒绝、`size`/`ratio` 吸附、尺寸守卫复用。
- 快照层：写入/读取往返、脱敏视图替换、媒体复制不引用原路径。
- 能力矩阵：Agnes 两型号声明值与官方档位一致。

**部署**

- 改动集中在适配器层与新增工具，`flutter build macos --release` + `scripts/deploy_local.sh` 常规部署。
