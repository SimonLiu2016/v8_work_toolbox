## 1. 音频拼接与转码回退强化 (AudioToolkit & Baker)

- [x] 1.1 在 `FfmpegAudioToolkit.concat` 中实现流拷贝失败时自动回退到 `-c:a libmp3lame -b:a 128k` 重编码
- [x] 1.2 在 `RealMeetingBaker._synthesizeToFile` 中捕获拼接过程中的具体异常信息，杜绝静默失败并传递真实错误
- [x] 1.3 在 `RealMeetingBaker.rebuildAudio` 中确保音频文件大于 0 字节才判定为就绪，并在遇到历史 0 字节损坏文件时自动清理并重新生成

## 2. 状态模型与错误结构化记录 (Models & Service)

- [x] 2.1 在 `TurnGroupAudio` 与 `MeetingBakeState` 中引入可选的 `failureReason` 错误原因字段并支持序列化与拷贝
- [x] 2.2 在 `RealMeetingBaker.bake` 中将具体的 TTS 错误与拼接错误记录到对应失败组中，随状态落盘
- [x] 2.3 在 `RealMeetingService` 与 `RealMeetingsController` 中透出失败明细与诊断信息

## 3. 界面展示与友好交互改造 (UI & UX)

- [x] 3.1 在 `RealMeetingDetail` 概览页中增加合成失败组展开列表卡片，展示失败轮次、发言人与具体原因
- [x] 3.2 优化 `RealMeetingPanel` 与详情顶部主操作栏：失败时提供明确的“重试失败组”与“修复整场音频”入口，杜绝无反馈原地卡死
- [x] 3.3 验证已生成或存在静音占位的真实会议可正常触发播放、文稿联动与进度记录

## 4. 自动化测试与真机环境验证

- [x] 4.1 编写或更新单元测试，验证长文本分段拼接在 WAV/MP3 混杂输入下的转码回退及错误透出
- [x] 4.2 执行 `./scripts/deploy_local.sh` 重新构建、部署并验证本机真实会议（含 10-29 会议）成功重新合成与播放
