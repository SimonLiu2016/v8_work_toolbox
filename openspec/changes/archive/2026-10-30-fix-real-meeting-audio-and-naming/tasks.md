## 1. 去掉懒解析门禁

- [x] 1.1 从 `AudioToolkit` 接口与 `FfmpegAudioToolkit` 删除 `isAvailable`
- [x] 1.2 `real_meeting_baker.rebuildAudio` 去掉 `if (_audio.isAvailable)`，无条件调用 `concat`，失败向上抛
- [x] 1.3 `real_meeting_baker._synthesizeToFile` 去掉 `if (!_audio.isAvailable)` 的"只保留第一段"分支；多段拼接失败时返回失败
- [x] 1.4 多段拼接失败时该组 SHALL 标记 `failed`（而不是报告成功）

## 2. 发布前校验

- [x] 2.1 `rebuildAudio` 返回前检查整篇音频文件是否存在；不存在时 `Clip.audioPath` 置空（占位）
- [x] 2.2 `RealMeetingService._publish` 对占位素材照常写入索引（让用户看得见、修得了）
- [x] 2.3 `bake` 的返回值区分"逐组成功"与"整篇可用"，界面据此给出不同提示
- [x] 2.4 确认播放器遇到空 `audioPath` 时给出可操作提示，且连续播放会跳过而不是卡住

## 3. 「生成音频」按来源分流

- [x] 3.1 `it_meeting_listening_page._bake()`：待生成集合按 `sourceId` 分成两组
- [x] 3.2 公开素材沿用 `ClipBaker` 的既有路径
- [x] 3.3 真实会议调用 `RealMeetingService.bake`（续跑，复用逐组音频）
- [x] 3.4 两类都处理完后合并刷新索引，进度提示覆盖两类
- [x] 3.5 无缺失时提示改为「当前没有需要生成的素材」

## 4. 会议显示名

- [x] 4.1 `MeetingSpeakerSettings` 增加 `displayTitle`（含 `copyWithTitle`）
- [x] 4.2 `RealMeetingService.renameMeeting(meetingId, title)` → 写覆盖层 + 重建索引
- [x] 4.3 `_publish` 使用 `displayTitle` 作为 `Clip.title`（为空回落文稿标题）
- [x] 4.4 真实会议面板的会议 chip 提供重命名入口；支持清空回落
- [x] 4.5 播放器标题与逐字稿页标题同步显示新名字

## 5. 测试

- [x] 5.1 假 `AudioToolkit` 改为可模拟"拼接失败"，覆盖"失败时不产出假素材"
- [x] 5.2 单元测试：整篇音频缺失 → 素材以占位形态发布（`audioPath` 为空）
- [x] 5.3 单元测试：多段拼接失败 → 该组 `failed`，且不产出被截断的音频
- [x] 5.4 单元测试：`displayTitle` 生效、清空后回落、重新导入不丢失
- [x] 5.5 端到端：构造"逐组音频齐全但没有整篇 mp3"的损坏状态 → 走「生成音频」重建 → 素材可播且未重新合成逐组音频

## 6. 验证与收尾

- [ ] 6.1 本机实机验证：对已损坏的 `rm_91ac2104ca11dd37` 点「生成音频」，确认几秒内修复且 TTS 调用为 0（由 `redesign-listening-practice-layout` 任务 12.7 验收覆盖）
- [ ] 6.2 新导入一场会议，确认整篇音频文件真实产出、播放正常（由 `redesign-listening-practice-layout` 任务 12.7 验收覆盖）
- [ ] 6.3 改名后确认列表 / 播放器 / 逐字稿标题一致，原稿 H1 未变（由 `redesign-listening-practice-layout` 任务 12.8 验收覆盖）
- [x] 6.4 `flutter analyze` 无新增告警；既有测试全绿
- [x] 6.5 归档前确认顺序：`add-real-meeting-import` → `fix-transcript-format-tolerance` → 本 change
