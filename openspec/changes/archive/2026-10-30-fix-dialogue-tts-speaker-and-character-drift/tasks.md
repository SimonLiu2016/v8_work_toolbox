## 1. 台词纯净化与说话人精准提取服务

- [x] 1.1 在 `PromptAssembler` 中实现 `cleanDialogueForSpeech(String dialogue)` 方法，使用多层健壮正则剔除人名前缀、内心 OS 标记、引号与预估秒数
- [x] 1.2 在 `PromptAssembler` 中实现 `extractSpeakerName(String dialogue)` 方法，从台词头部结构精准提取说话人姓名
- [x] 1.3 改造 `PromptAssembler.buildVideoGenPrompt`，全面接入 `cleanDialogueForSpeech` 与 `extractSpeakerName`，彻底禁止元数据进入视频口型

## 2. TTS 音频合成与说话人音色对齐

- [x] 2.1 改造 `StudioTtsService.synthesizeEpisode`，在朗读前调用 `cleanDialogueForSpeech` 净化台词文本
- [x] 2.2 改造 `sound_design_panel.dart` 中的 `resolveVoiceId` 逻辑：优先匹配 `extractSpeakerName` 对应的说话人角色卡音色，彻底废弃盲选 `characterIds.first`

## 3. 本地节拍转换隔离心声实体与发型双重锁定

- [x] 3.1 改造 `AiConstraintEngine.convertScenesToShots`：当台词为内心独白时，出场角色匹配范围剔除台词正文，防止非在场第三人被误加入 `characterIds`
- [x] 3.2 改造 `PromptAssembler.resolveCharacterStaging`：在多角色同框时无条件追加角色的 `facialFeaturesZh` 容貌与发型描述，防止全景/远景镜头下发型画风突变

## 4. 验证与工程构建部署

- [x] 4.1 编写单元测试验证：台词纯净剥离、说话人提取精准对齐、内心戏不误召非在场实体、同框全景发型文本锁定
- [x] 4.2 运行代码静态检查与全套测试
- [x] 4.3 按照工程级规范执行 `./scripts/deploy_local.sh` 编译 Release 并部署本地应用
