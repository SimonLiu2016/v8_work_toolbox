## 1. 首帧尺寸守卫

- [x] 1.1 `lib/tools/ai_video_studio/services/video_gen_adapter.dart`：`_prepareKeyframeDataUri` 增加下限守卫——边长小于 256 像素时抛 `StateError`，信息指明「关键帧尺寸过小」并建议重新生成
- [x] 1.2 同处：确认上限行为不变（>720×1280 仍等比缩小）；**不把小图放大**——放大不增细节，只会让用户误以为变清晰
- [x] 1.3 错误信息不得透出供应商指向 `first_frame` 参数的原文（用户看不出是自己的图太小）

## 2. 错误体甄别

- [x] 2.1 新增 `_QueryOutcome` 信封类型：`body` / `rateLimited` / `errorMessage` / `notFound`
- [x] 2.2 `_queryTask` 改为返回信封；甄别规则是**先看 `body['error']` 是否非空**，再看业务字段（实测：正常响应该字段为 null）
- [x] 2.3 命中 `error.code == 429` 或 message 含限流字样 → `rateLimited = true`
- [x] 2.4 HTTP 404 → `notFound = true`，错误信息提示「确认保存的是 video_id 而非 task_id」
- [x] 2.5 `_pollUntilDone` 处理信封：`rateLimited` 时退避并保持上一次已知状态与进度，**不得依据错误体更新进度或阶段**；`notFound` 立即抛错

## 3. 两条查询路径各自解析

- [x] 3.1 主路径 `/agnesapi` 的 URL 从顶层 `url` 读（现状已对，抽出为独立函数）
- [x] 3.2 兜底路径 `/v1/videos/<id>` 的 URL 从 `metadata.url` 读（**当前 bug：读顶层读不到**）
- [x] 3.3 兜底路径也取不到 URL 时明确抛错，MUST NOT 返回空串让上层空转至预算耗尽

## 4. 阶段判定改用 started_at

- [x] 4.1 `_pollUntilDone` 的阶段切换改判 `started_at` 非空（响应字段，Unix 秒），不再匹配状态字符串
- [x] 4.2 状态字符串只保留两个用途：判 `completed`、判 `failed`
- [x] 4.3 文档外状态值（含实测发现的第五态 `pending`）一律视为「还在跑」，继续轮询，不清空已有阶段信息

## 5. 注释记录实测协议形态

- [x] 5.1 `AgnesVideoAdapter` 类注释补实测结论与日期：第五态 `pending`、HTTP 200 限流体、两套 URL 位置、云端 URL 长期有效、三 ID 实测相同
- [x] 5.2 注释标注为「当时观察到的事实」而非永久约束——供应商改协议时注释会过期，但无害

## 6. 测试

- [x] 6.1 假后端返回 HTTP 200 + `{"error":{"code":429,...}}` 时，适配器识别为限流并退避，不依据该响应更新进度
- [x] 6.2 假后端只实现兜底路径（URL 在 `metadata.url`）时，适配器能取回视频
- [x] 6.3 假后端先返回 `pending` + `started_at: null`、再返回 `in_progress` + `started_at` 非空，验证阶段正确切换
- [x] 6.4 首帧 100×100 时本地拒绝，错误信息含「尺寸过小」且不含供应商的 `first_frame` 原文
- [x] 6.5 改写 `test/senseaudio_video_adapter_test.dart` 与 `test/agnes_studio_pipeline_test.dart` 中按旧形态编写的假后端（错误体甄别会改变它们的响应路径）
- [x] 6.6 运行 `flutter test` 与 `flutter analyze`，确认无回归
