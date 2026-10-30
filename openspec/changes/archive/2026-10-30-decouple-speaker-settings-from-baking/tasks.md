## 1. 数据：按组记录实际音色

- [x] 1.1 `TurnGroupAudio` 增加 `voiceId`（该组实际合成用的音色），含 JSON 读写
- [x] 1.2 `bake` 合成每组时把实际使用的音色写入 `state.groups[i].voiceId`
- [x] 1.3 `rebuildAudio` 组装 `Clip` 时，`SpeakerTurn.voice` 取组记录的**实际音色**；无记录（旧数据）时才回落到当前设定
- [x] 1.4 旧数据无记录时**不**视为待更新

## 2. 服务：设定与烘焙解耦

- [x] 2.1 `setSpeakerVoice` 改为：写覆盖层 + 刷新派生素材，**不调用 baker**
- [x] 2.2 `mergeSpeakers` / `unmergeSpeaker` / `markSlotAsMe` 同样不再触发合成
- [x] 2.3 新增 `pendingGroups(meeting)` → 待更新的组下标列表（设定音色 ≠ 组记录音色）
- [x] 2.4 新增 `rebakeGroups(meeting, indices, {onProgress, shouldCancel})`：只重合成指定组并重建整篇
- [x] 2.5 同一会议的整篇重建串行化（`_rebaking` 与 `_baking` 不得并发写同一 mp3）

## 3. 合成器：临时文件与取消

- [x] 3.1 `RealMeetingBaker.bake` 支持 `forceGroups`：指定组忽略已有文件、强制重合成
- [x] 3.2 强制重合成写入 `g<k>.new.mp3`，成功才 rename 覆盖 `g<k>.mp3`
- [x] 3.3 成功替换后更新该组 `voiceId`；失败则删临时文件、保留旧音频、该组仍为 `failed` 之外的"待更新"
- [x] 3.4 支持 `bool Function() shouldCancel`，只在组与组之间检查
- [x] 3.5 取消后照常重建整篇音频（时间戳按实际音频重算）

## 4. 界面

- [x] 4.1 `_busy` 拆成 `_importing` / `_baking` / `_rebaking`，各自只禁用对应按钮
- [x] 4.2 改音色 / 合并 / 标记「我」不再进入忙碌状态，操作后立即刷新 speakers 与下拉值
- [x] 4.3 真实会议面板显示「N 组音频待更新（当前仍是旧音色）」，为零时不显示
- [x] 4.4 面板提供「重新合成」按钮，点击后显示 `已完成/总数` 进度
- [x] 4.5 重新合成进行中提供「取消」，取消后恢复为可操作状态并提示保留了多少组
- [x] 4.6 「更新素材」「生成音频」「导入逐字稿」在重新合成期间保持可用

## 5. 测试

- [x] 5.1 改音色后：覆盖层已写、`speakers` 已变、**TTS 调用为 0**、下拉值回填
- [x] 5.2 `pendingGroups` 在改音色后返回该槽位组，重新合成后归零
- [x] 5.3 重新合成单组失败：旧音频文件仍在、该组仍待更新、其余组完成
- [x] 5.4 取消：已完成组使用新音色，未完成组仍待更新，整篇音频可播
- [x] 5.5 `Clip.turns[].voice` 在未重烘时仍显示**旧音色**（追溯不撒谎）
- [x] 5.6 旧数据（无 `voiceId`）不被标记为待更新

## 6. 验证与收尾

- [ ] 6.1 实机：改一个说话人的音色，确认界面立即回填、按钮不灰、TTS 无请求（由 `redesign-listening-practice-layout` 任务 12.9 验收覆盖）
- [ ] 6.2 实机：点「重新合成」，确认进度可见、可取消；完成后面板提示消失、声音确实变了（由 `redesign-listening-practice-layout` 任务 12.9 验收覆盖）
- [ ] 6.3 实机：重新合成进行中仍能打开「导入逐字稿」与改另一个说话人的设定（由 `redesign-listening-practice-layout` 任务 12.9 验收覆盖）
- [x] 6.4 `flutter analyze` 无新增告警；既有测试全绿
- [x] 6.5 归档顺序：`add-real-meeting-import` → `fix-transcript-format-tolerance` → `fix-real-meeting-audio-and-naming` → 本 change
