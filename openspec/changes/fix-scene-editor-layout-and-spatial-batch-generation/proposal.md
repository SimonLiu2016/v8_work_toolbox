# Proposal: 修复场景资产编辑器溢出与全息组图生图韧性容错

## Why

用户在连续剧 IP 主库中编辑场景资产时，因界面顶栏将大量长文本按钮并列塞入单行，且底抽屉受 Flutter M3 默认 640px 最大宽度钳制，导致“编辑场景资产”后面的批量操作、删除、保存与关闭按钮严重溢出到窗口之外无法操作。此外，“一键生成全息组图 (7视角)”等连续生图任务在遇到供应商 API 速率限制 (429) 或偶发网络抖动时缺乏重试与失败隔离，往往在生成 1~2 张后直接因异常跳出循环而中断，且弹窗关闭后直接被中止，严重影响工业化资产生产流程。

本提案实施“两步走”战略的第 1 步：优先治愈界面严重溢出与连续生图的断流问题，建立底层自动退避重试与批处理故障隔离机制，为后续全工坊长任务统一队列奠定基石。

## What Changes

1. **场景资产编辑器界面语义分层（方案 A）**：
   - 将“AI 全息解构七方位 (仅文字)”与“一键生成全息组图 (7视角)”移入“七方位空间全息档案”专属小节栏头部右侧，与下方参考图库风格高度对称。
   - 顶部操作栏仅保留模态生命周期动作：标题、删除场景、保存修改与关闭按钮，彻底消除横向挤压。
   - 解除 `showModalBottomSheet` 移动端 640px 默认约束，传入最大 1200px 或 92% 桌面窗口宽度的弹性约束。
2. **底层图像生成适配器自动退避重试**：
   - 在 `SystemAiImageAdapter`（及核心请求层）增加带随机抖动的指数退避重试机制（针对 HTTP 429 限流、5xx 服务端错误及 Socket/Timeout 异常重试 3 次，间隔 1.5s/3s/6s）。
3. **七方位空间全息组图批量容错与生命周期解耦**：
   - 组图循环支持单方位故障隔离：单张生图失败不中止后续视角的生成；
   - 维护方位生成状态矩阵，成功视角即时落盘与绑定，失败视角明确提示并提供单项重试；
   - 异步批处理任务脱离弹窗 `mounted` 强绑定，弹窗关闭后后台任务继续完成落盘与场景元数据保存。

## Capabilities

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 增加场景资产编辑器的宽屏适配与操作分层规范，规范全息空间档案的批量生图断点容错、故障隔离与 API 自动重试机制。

## Impact
- **代码影响**：
  - `lib/tools/ai_video_studio/ui/series_page.dart`（`_ScenesTabState._openEditor`、`_SceneEditorSheet` 与 `_generateAllSpatialImages`）
  - `lib/tools/ai_video_studio/services/image_gen_adapter.dart`（`SystemAiImageAdapter` 请求核心与重试策略）
- **依赖与 API**：无外部新依赖引入，完全兼容既有 `ImageGenRequest`、`AiConfigStore` 与本地存储规范。
- **向下兼容**：场景数据结构与 JSON 持久化格式不变。
