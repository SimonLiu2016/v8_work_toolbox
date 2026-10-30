# Technical Design: 场景资产编辑器排版重构与生图韧性机制

## Context

见 `proposal.md`。当前 `lib/tools/ai_video_studio/ui/series_page.dart` 中的 `_SceneEditorSheet` 因底抽屉默认 640px 约束和单行过度堆叠导致严重右侧溢出；同时 `_generateAllSpatialImages` 在 `_SceneEditorSheetState` 内部以原始 `for` 循环连续调用 `SystemAiImageAdapter.generate`，由于缺少重试与单步故障隔离，极易触发 API 限流 (429) 或网络中断导致批量生成半途中断。

## Goals / Non-Goals

**Goals:**
- **消除横向溢出**：重构 `_SceneEditorSheet` 顶栏排版，解除 640px 限制，顶栏仅保留基础生命周期动作，七方位全息批量操作移入对应小节右侧。
- **底层自动退避重试**：在 `SystemAiImageAdapter` 的核心请求环节增加针对 HTTP 429、5xx、Socket/Timeout 的指数退避重试（最多 3 次，1.5s, 3s, 6s）。
- **批处理故障隔离与持久化保护**：在 `_generateAllSpatialImages` 中实现每个方位的独立异常捕获与状态标记；单图失败不阻断其余方位的生成，完成部分即时写入场景配置。
- **生命周期解耦防护**：生成循环不因 `!mounted` 粗暴丢失已生成的图片成果。

**Non-Goals:**
- 不在本次改动中推翻并全局重构 `StudioTaskQueue`（工坊全局任务中枢归并在 Step 2 中推进）。
- 不更改既有场景资产 `SceneCard` 及 7 方位空间数据持久化 JSON 的 Schema。

## Decisions

### 决策 1：`showModalBottomSheet` 采用桌面宽屏弹性约束（方案 A）
- **实现方案**：
  在 `_ScenesTabState._openEditor` 调用 `showModalBottomSheet` 时，传入：
  ```dart
  constraints: BoxConstraints(
    maxWidth: (MediaQuery.of(context).size.width * 0.92).clamp(900.0, 1200.0),
  ),
  ```
- **排版分层**：
  - 顶栏：`Text('编辑场景资产')` + `Spacer()` + `[删除场景]` + `[保存修改]` + `[关闭]`；
  - 七方位空间全息档案头部：`Text('七方位空间全息档案')` + `Spacer()` + `[AI 全息解构七方位 (仅文字)]` + `[一键生成全息组图 (7视角)]`。
- **备选方案及淘汰原因**：
  - 备选方案 B（顶栏双行）：将批量操作放在顶栏第二行，依然会增加弹窗顶部的认知负荷，且与下方参考图库的操作风格不一致。

### 决策 2：`SystemAiImageAdapter` 内置指数退避重试
- **实现方案**：
  封装通用的异步重试函数 `_executeWithRetry<T>`：
  - 监听 `StateError`（内含 429/5xx）、`http.ClientException`、`SocketException`、`TimeoutException`；
  - 遇到可重试异常时，计算延迟 `delay = baseDelay * (2 ^ attempt) + jitter`，输出调试日志并等待；
  - 最多重试 3 次；若重试耗尽则正常抛出异常。
- **备选方案及淘汰原因**：
  - 备选仅在调用方（如 `series_page.dart`）写 try-catch 重试：会导致每个生成调用点（角色、道具、分镜）都需要复制一遍重试逻辑，无法惠及工坊其他生图场景。

### 决策 3：`_generateAllSpatialImages` 单步故障隔离与汇总反馈
- **实现方案**：
  - 循环迭代 `SceneDirection.values` 时，每个方位使用独立的 `try-catch` 块；
  - 成功时更新 `_refs` 与 `_spatialViews[dir.name]`，并立即落盘绑定；
  - 失败时将方位记录到 `failedDirections` 列表，并更新状态；
  - 全部 7 方位尝试完毕后，若全部成功提示成功；若部分失败提示：“已生成 X/7 个视角，[xx]视角失败，可单独生成此视角”；
  - 生成过程中若弹窗被关闭（`!mounted`），后台继续按当前已持有参数完成剩余视角的生图与落盘，确保不出现数据丢失。

## Risks / Trade-offs

- **[Risk] 连续 7 张生图遇到退避时总耗时可能延长（如 2~4 分钟）**  
  → **Mitigation**: 界面提供清晰的“正在生成 (X/7 方位名)...”进度条状态；且单步完成后即时落盘，用户随时可见已成功的方位成果。
- **[Risk] 429 遇到配额耗尽（Quota Exhausted）而非暂时限流**  
  → **Mitigation**: 错误信息透出具体的报错详情（如余额不足或账户欠费），避免无谓重试死循环。
